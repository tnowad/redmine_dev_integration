# frozen_string_literal: true

require 'json'
require_relative 'provider_user_resolver'

module RedmineDevIntegration
  class BitbucketPullRequestProcessor
    def initialize; end

    def call(external_provider_event)
      payload = parse_payload(external_provider_event.payload)
      return false unless payload.is_a?(Hash)
      return false unless external_provider_event.provider == 'bitbucket'
      return false unless external_provider_event.event_type.start_with?('pullrequest')

      repository = external_repository_for(payload)
      return false unless repository

      pull_request = find_or_initialize_pull_request(repository, payload)
      return false unless pull_request.number.present?

      update_pull_request(pull_request, payload)
      return false if pull_request.title.blank? || pull_request.url.blank? || pull_request.state.blank?

      pull_request.save!
      pull_request.link_issues_from_texts(
        pull_request.title,
        pull_request.body,
        pull_request.source_branch,
        pull_request.target_branch
      )
      process_linked_issues(pull_request, payload, external_provider_event)
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

    def find_or_initialize_pull_request(repository, payload)
      ExternalPullRequest.find_or_initialize_by(
        provider: 'bitbucket',
        external_repository: repository,
        number: payload.dig('pullrequest', 'id')
      )
    end

    def update_pull_request(pull_request, payload)
      pr_data = payload['pullrequest'] || {}

      pull_request.number = pr_data['id'] if pr_data['id'].present?
      pull_request.title = pr_data['title']
      pull_request.body = pr_data['description'] || pr_data['body']
      pull_request.url = pr_data.dig('links', 'html', 'href').presence || payload.dig('links', 'html', 'href')
      pull_request.state = state_for(pr_data)
      pull_request.author_login = pr_data.dig('author', 'username') || pr_data.dig('author', 'display_name')
      pull_request.source_branch = pr_data.dig('source', 'branch', 'name')
      pull_request.target_branch = pr_data.dig('destination', 'branch', 'name')
      pull_request.source_sha = pr_data.dig('source', 'commit', 'hash')
      pull_request.target_sha = pr_data.dig('destination', 'commit', 'hash')
      pull_request.merge_commit_sha = pr_data.dig('merge_commit', 'hash')
      pull_request.merged = pr_data['state'] == 'MERGED'
      pull_request.merged_at = time_value(pr_data['updated_on']) if pull_request.merged
      pull_request.opened_at = time_value(pr_data['created_on'])
      pull_request.closed_at = time_value(pr_data['updated_on']) if %w[MERGED DECLINED].include?(pr_data['state'])
      pull_request.last_event_at = time_value(pr_data['updated_on'])
    end

    def state_for(pr_data)
      case pr_data['state']
      when 'OPEN' then 'open'
      when 'MERGED' then 'closed'
      when 'DECLINED' then 'closed'
      else 'open'
      end
    end

    def time_value(value)
      return if value.blank?

      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def process_linked_issues(pull_request, payload, external_provider_event)
      event_type = event_type_for(external_provider_event)
      return unless event_type

      login = pull_request.author_login || payload.dig('actor', 'username')
      note = pull_request_note(pull_request, payload, event_type)

      RedmineDevIntegration::ProviderUserResolver.with_resolved_user(
        provider: 'bitbucket',
        provider_login: login
      ) do
        pull_request.issues.find_each do |issue|
          automation_result = AutomationService.new.call(
            issue: issue,
            event_type: event_type,
            project: pull_request.external_repository.redmine_project,
            note: note,
            marker: automation_marker(pull_request, event_type, issue),
            external_provider_event: external_provider_event
          )

          next if automation_result.processed?
          next unless event_type == 'pr_closed_without_merge'

          AuditNoteService.new.call(
            issue: issue,
            note: note,
            marker: audit_marker(pull_request, event_type, issue),
            provider_url: pull_request.url,
            external_object_id: pull_request.id,
            user: User.current
          )
        end
      end
    end

    def event_type_for(external_provider_event)
      case external_provider_event.event_type
      when 'pullrequest:created' then 'pr_opened'
      when 'pullrequest:fulfilled' then 'pr_merged'
      when 'pullrequest:rejected' then 'pr_closed_without_merge'
      end
    end

    def pull_request_note(pull_request, payload, event_type)
      parts = ["PR #{event_type.to_s.sub('pr_', '').tr('_', ' ')}: ##{pull_request.number}"]
      parts << pull_request.url if pull_request.url.present?
      parts << "source=#{pull_request.source_branch}" if pull_request.source_branch.present?
      parts << "target=#{pull_request.target_branch}" if pull_request.target_branch.present?
      parts.join(' | ')
    end

    def audit_marker(pull_request, event_type, issue)
      "bitbucket:pr:#{pull_request.id}:#{event_type}:#{issue.id}"
    end

    def automation_marker(pull_request, event_type, issue)
      "bitbucket:pr:#{pull_request.id}:#{event_type}:#{issue.id}"
    end
  end
end
