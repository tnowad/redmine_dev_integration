# frozen_string_literal: true

require 'json'
require_relative 'provider_user_resolver'

module RedmineDevIntegration
  class GitlabPipelineProcessor
    def initialize; end

    def call(external_provider_event)
      payload = parse_payload(external_provider_event.payload)
      return false unless payload.is_a?(Hash)
      return false unless external_provider_event.provider == 'gitlab'
      return false unless external_provider_event.event_type == 'Pipeline Hook'

      repository = external_repository_for(payload)
      return false unless repository

      object_attributes = payload['object_attributes'] || {}
      provider_build_id = object_attributes['id'].to_s
      return false if provider_build_id.blank?

      build = ExternalBuild.find_or_initialize_by(
        provider: 'gitlab',
        external_repository: repository,
        provider_build_id: provider_build_id
      )

      build.build_number = object_attributes['iid'].presence || object_attributes['id']
      build.name = object_attributes['name'].presence || "Pipeline #{provider_build_id}"
      build.status = normalized_status(object_attributes['status'])
      build.conclusion = object_attributes['status']
      build.url = object_attributes['url']
      build.sha = object_attributes['sha']
      build.ref = object_attributes['ref']
      build.branch_name = object_attributes['ref']
      build.author_login = payload.dig('user', 'username').presence || payload.dig('user', 'name')
      build.started_at = time_value(object_attributes['created_at'])
      build.finished_at = time_value(object_attributes['finished_at'])
      build.last_event_at = time_value(object_attributes['updated_at'] || object_attributes['finished_at'])

      return false unless build.build_number.present? && build.name.present? && build.status.present?

      build.save!
      text_link_result = build.link_issues_from_texts(
        build.name,
        build.ref,
        build.branch_name,
        payload.dig('commit', 'message'),
        payload.dig('commit', 'title')
      )
      link_traced_issues(build, trace_issues_for(build.external_repository, build.sha)) if text_link_result.issue_ids.empty?
      process_linked_issues(build, external_provider_event)
      true
    end

    private

    def parse_payload(payload)
      return payload if payload.is_a?(Hash)
      return {} if payload.blank?

      JSON.parse(payload)
    rescue JSON::ParserError
      nil
    end

    def external_repository_for(payload)
      RedmineDevIntegration::ExternalRepositoryResolver.gitlab(payload)
    end

    def normalized_status(status)
      case status.to_s
      when 'created', 'pending'
        'queued'
      when 'running'
        'in_progress'
      when 'success'
        'success'
      when 'failed'
        'failed'
      when 'canceled', 'cancelled'
        'canceled'
      when 'skipped'
        'skipped'
      else
        'unknown'
      end
    end

    def time_value(value)
      return if value.blank?
      return value.in_time_zone if value.respond_to?(:in_time_zone) && !value.is_a?(String)

      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def process_linked_issues(build, external_provider_event)
      event_type = event_type_for(build)
      return unless event_type

      login = build.author_login
      note = build_note(build, event_type)

      RedmineDevIntegration::ProviderUserResolver.with_resolved_user(
        provider: 'gitlab',
        provider_login: login
      ) do
        build.issues.find_each do |issue|
          AutomationService.new.call(
            issue: issue,
            event_type: event_type,
            project: build.external_repository.redmine_project,
            note: note,
            marker: automation_marker(build, event_type),
            external_provider_event: external_provider_event
          )
        end
      end
    end

    def trace_issues_for(external_repository, sha)
      RedmineDevIntegration::ShaIssueTracer.new.call(
        external_repository: external_repository,
        sha: sha
      )
    rescue StandardError
      []
    end

    def link_traced_issues(build, issue_ids)
      issue_ids.each do |issue_id|
        ExternalBuildIssue.find_or_create_by!(external_build_id: build.id, issue_id: issue_id)
      end
    end

    def event_type_for(build)
      case build.status
      when 'failed'
        'build_failed'
      when 'success'
        'build_success'
      end
    end

    def build_note(build, event_type)
      return "Build failed: #{build.name} | status=#{build.conclusion || build.status}" if event_type == 'build_failed'

      nil
    end

    def automation_marker(build, event_type)
      "build:#{build.provider}:#{build.id}:#{event_type}"
    end
  end
end
