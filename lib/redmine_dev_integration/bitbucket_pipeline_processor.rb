# frozen_string_literal: true

require 'json'

module RedmineDevIntegration
  class BitbucketPipelineProcessor
    def initialize; end

    def call(external_provider_event)
      payload = parse_payload(external_provider_event.payload)
      return false unless payload.is_a?(Hash)
      return false unless external_provider_event.provider == 'bitbucket'
      return false unless %w[repo:commit_status_created repo:commit_status_updated].include?(external_provider_event.event_type)

      repository = external_repository_for(payload)
      return false unless repository

      commit_status = payload['commit_status'] || {}
      state = commit_status['state'] || ''
      provider_build_id = (commit_status['key'] || commit_status['uuid']).to_s
      return false if provider_build_id.blank?

      build = ExternalBuild.find_or_initialize_by(
        provider: 'bitbucket',
        external_repository: repository,
        provider_build_id: provider_build_id
      )

      build.build_number = commit_status['key']
      build.name = commit_status['name'].presence || commit_status['description'].presence || "Commit status #{provider_build_id}"
      build.status = normalized_status(state)
      build.conclusion = state
      build.url = commit_status['url'] || commit_status.dig('links', 'html', 'href')
      build.sha = commit_status.dig('commit', 'hash') || commit_status['commit']
      build.ref = commit_status.dig('commit', 'ref') || commit_status['refname']
      build.branch_name = commit_status.dig('commit', 'branch') || commit_status['refname']
      build.author_login = commit_status.dig('user', 'username') || commit_status.dig('user', 'display_name') || commit_status.dig('author', 'username')
      build.started_at = time_value(commit_status['created_on'])
      build.finished_at = %w[SUCCESSFUL FAILED STOPPED].include?(state) ? time_value(commit_status['updated_on']) : nil
      build.last_event_at = time_value(commit_status['updated_on'] || external_provider_event.created_at)

      return false unless build.build_number.present? && build.name.present? && build.status.present?

      build.save!
      text_link_result = build.link_issues_from_texts(
        build.name,
        build.branch_name,
        build.ref,
        commit_status['description']
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
      RedmineDevIntegration::ExternalRepositoryResolver.bitbucket(payload)
    end

    def normalized_status(state)
      case state.to_s
      when 'INPROGRESS' then 'in_progress'
      when 'SUCCESSFUL' then 'success'
      when 'FAILED' then 'failed'
      when 'STOPPED' then 'canceled'
      else 'unknown'
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

      note = build_note(build, event_type)

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
