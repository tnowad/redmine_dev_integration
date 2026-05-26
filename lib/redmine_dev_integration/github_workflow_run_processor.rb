# frozen_string_literal: true

require 'json'
require_relative 'provider_user_resolver'

module RedmineDevIntegration
  class GitHubWorkflowRunProcessor
    def initialize; end

    def call(external_provider_event)
      payload = parse_payload(external_provider_event.payload)
      return false unless payload.is_a?(Hash)
      return false unless external_provider_event.provider == 'github'
      return false unless external_provider_event.event_type == 'workflow_run'

      repository = external_repository_for(payload)
      return false unless repository

      workflow_run = payload['workflow_run'] || {}
      provider_build_id = workflow_run['id'].to_s
      return false if provider_build_id.blank?

      build = ExternalBuild.find_or_initialize_by(
        provider: 'github',
        external_repository: repository,
        provider_build_id: provider_build_id
      )

      build.build_number = workflow_run['run_number']
      build.name = workflow_run['display_title'].presence || workflow_run['name'].presence || "Workflow run #{provider_build_id}"
      build.status = normalized_status(workflow_run)
      build.conclusion = workflow_run['conclusion']
      build.url = workflow_run['html_url']
      build.sha = workflow_run['head_sha']
      build.ref = workflow_run['head_branch']
      build.branch_name = workflow_run['head_branch']
      build.author_login = workflow_run.dig('actor', 'login')
      build.started_at = time_value(workflow_run['run_started_at'] || workflow_run['created_at'])
      build.finished_at = time_value(workflow_run['updated_at']) if workflow_run['status'].to_s == 'completed'
      build.last_event_at = time_value(workflow_run['updated_at'] || external_provider_event.created_at)

      return false unless build.build_number.present? && build.name.present? && build.status.present?

      build.save!
      text_link_result = build.link_issues_from_texts(
        build.name,
        build.branch_name,
        build.ref,
        workflow_run.dig('head_commit', 'message')
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
      RedmineDevIntegration::ExternalRepositoryResolver.github(payload)
    end

    def normalized_status(workflow_run)
      case workflow_run['status'].to_s
      when 'queued', 'requested', 'waiting'
        'queued'
      when 'in_progress'
        'in_progress'
      when 'completed'
        case workflow_run['conclusion'].to_s
        when 'success'
          'success'
        when 'failure'
          'failed'
        when 'cancelled', 'canceled'
          'canceled'
        when 'skipped'
          'skipped'
        else
          'unknown'
        end
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
        provider: 'github',
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
