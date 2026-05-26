# frozen_string_literal: true

require 'json'
require_relative 'provider_user_resolver'

module RedmineDevIntegration
  class GitlabMergeRequestProcessor
    def initialize; end

    def call(external_provider_event)
      payload = parse_payload(external_provider_event.payload)
      return false unless payload.is_a?(Hash)
      return false unless external_provider_event.provider == 'gitlab'
      return false unless external_provider_event.event_type == 'Merge Request Hook'

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
      RedmineDevIntegration::ExternalRepositoryResolver.gitlab(payload)
    end

    def find_or_initialize_pull_request(repository, payload)
      ExternalPullRequest.find_or_initialize_by(
        provider: 'gitlab',
        external_repository: repository,
        number: pull_request_number(payload)
      )
    end

    def pull_request_number(payload)
      payload.dig('object_attributes', 'iid') || payload.dig('merge_request', 'iid') || payload['iid'] || payload['number']
    end

    def update_pull_request(pull_request, payload)
      action = payload.dig('object_attributes', 'action').to_s
      mr_data = payload['object_attributes'] || payload['merge_request'] || {}

      pull_request.number = pull_request_number(payload)
      pull_request.title = mr_data['title'] || payload['title']
      pull_request.body = mr_data['description'] || mr_data['body'] || payload['description'] || payload['body']
      pull_request.url = mr_data['web_url'] || mr_data['url'] || payload['web_url'] || payload['url']
      pull_request.state = state_for(action, mr_data)
      pull_request.author_login = payload.dig('user', 'username') || mr_data.dig('author', 'username') || payload.dig('user', 'name')
      pull_request.source_branch = mr_data['source_branch']
      pull_request.target_branch = mr_data['target_branch']
      pull_request.source_sha = mr_data.dig('last_commit', 'id') || mr_data['sha'] || payload['sha']
      pull_request.target_sha = mr_data.dig('diff_refs', 'start_sha') || mr_data['target_branch_sha'] || payload['target_branch_sha']
      pull_request.merge_commit_sha = mr_data['merge_commit_sha'] || payload['merge_commit_sha']
      pull_request.merged = merged_for(action, mr_data)
      pull_request.merged_at = time_value(mr_data['merged_at'] || payload['merged_at'])
      pull_request.opened_at = time_value(mr_data['created_at'] || payload['created_at'])
      pull_request.closed_at = time_value(mr_data['closed_at'] || payload['closed_at'] || (pull_request.merged? ? mr_data['merged_at'] : nil))
      pull_request.last_event_at = time_value(mr_data['updated_at'] || payload['updated_at'] || payload['timestamp'])
    end

    def state_for(action, mr_data)
      return 'open' if %w[open reopen update].include?(action) || mr_data['state'].to_s == 'opened'
      return 'closed' if action == 'close' || action == 'merge' || mr_data['state'].to_s == 'closed' || mr_data['state'].to_s == 'merged'

      'open'
    end

    def merged_for(action, mr_data)
      return true if action == 'merge'
      return true if mr_data['state'].to_s == 'merged'

      false
    end

    def time_value(value)
      return if value.blank?

      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def process_linked_issues(pull_request, payload, external_provider_event)
      event_type = event_type_for(payload, pull_request)
      return unless event_type

      login = pull_request.author_login || payload.dig('user', 'username') || payload.dig('user', 'name')
      note = pull_request_note(pull_request, event_type)

      RedmineDevIntegration::ProviderUserResolver.with_resolved_user(
        provider: 'gitlab',
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

    def event_type_for(payload, pull_request)
      action = payload.dig('object_attributes', 'action').to_s
      return 'pr_opened' if action == 'open'
      return 'pr_merged' if action == 'merge' || (pull_request.state == 'closed' && pull_request.merged)
      return 'pr_closed_without_merge' if action == 'close' && pull_request.state == 'closed' && !pull_request.merged

      nil
    end

    def pull_request_note(pull_request, event_type)
      parts = ["PR #{event_type.to_s.sub('pr_', '').tr('_', ' ')}: ##{pull_request.number}"]
      parts << pull_request.url if pull_request.url.present?
      parts << "source=#{pull_request.source_branch}" if pull_request.source_branch.present?
      parts << "target=#{pull_request.target_branch}" if pull_request.target_branch.present?
      parts.join(' | ')
    end

    def audit_marker(pull_request, event_type, issue)
      "gitlab:pr:#{pull_request.id}:#{event_type}:#{issue.id}"
    end

    def automation_marker(pull_request, event_type, issue)
      "gitlab:pr:#{pull_request.id}:#{event_type}:#{issue.id}"
    end
  end
end
