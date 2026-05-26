# frozen_string_literal: true

require 'json'

module RedmineDevIntegration
  class GitlabPushBranchProcessor
    def initialize; end

    def call(external_provider_event)
      payload = parse_payload(external_provider_event.payload)
      return false unless payload.is_a?(Hash)
      return false unless external_provider_event.provider == 'gitlab'
      return false unless external_provider_event.event_type == 'Push Hook'

      ref = payload['ref'].to_s
      branch_name = branch_name_from_ref(ref)
      return false unless branch_name

      repository = external_repository_for(payload)
      return false unless repository

      branch = find_or_initialize_branch(repository, branch_name)
      branch.url = branch_url(payload, branch_name)
      branch.sha = payload['after'].presence if payload['after'].present?
      branch.state = deleted?(payload) ? 'deleted' : 'active'
      branch.deleted_at = Time.current if branch.deleted?
      branch.deleted_at = nil if branch.active?
      branch.save!
      commit_messages = PushCommitTextExtractor.extract(payload['commits'])
      branch.link_issues_from_texts(branch_name, *commit_messages)
      process_commits(payload['commits'], repository, branch_name)
      process_linked_issues(branch, branch_name, payload) if branch.active?
      process_smart_commits(payload, repository.redmine_project)
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

    def branch_name_from_ref(ref)
      return unless ref.start_with?('refs/heads/')

      ref.delete_prefix('refs/heads/')
    end

    def external_repository_for(payload)
      RedmineDevIntegration::ExternalRepositoryResolver.gitlab(payload)
    end

    def find_or_initialize_branch(repository, branch_name)
      ExternalBranch.find_or_initialize_by(external_repository: repository, name: branch_name)
    end

    def branch_url(payload, branch_name)
      web_url = payload.dig('project', 'web_url').to_s.presence || payload.dig('repository', 'homepage').to_s.presence || payload.dig('repository', 'url').to_s.presence
      return if web_url.blank?

      "#{web_url}/-/tree/#{branch_name}"
    end

    def deleted?(payload)
      payload['deleted'] == true || payload['after'].to_s == ('0' * 40)
    end

    def process_linked_issues(branch, branch_name, payload)
      branch.issues.find_each do |issue|
        note = branch_note(branch, branch_name, payload)
        marker = branch_marker(branch, issue)

        automation_result = AutomationService.new.call(
          issue: issue,
          event_type: 'branch_created',
          project: branch.external_repository.redmine_project,
          note: note,
          marker: marker
        )

        next if automation_result.processed?

        AuditNoteService.new.call(
          issue: issue,
          note: note,
          marker: marker,
          provider_url: branch.url,
          external_object_id: branch.id,
          user: User.current
        )
      end
    end

    def process_commits(commits, repository, branch_name)
      return unless commits.is_a?(Array)

      commits.each do |commit|
        next unless commit.is_a?(Hash)
        sha = commit['id'].to_s
        next if sha.blank?

        external_commit = ExternalCommit.find_or_initialize_by(
          provider: 'gitlab',
          external_repository: repository,
          provider_commit_id: sha
        )
        external_commit.sha = sha
        external_commit.short_sha = sha[0, 7]
        external_commit.message = commit['message'].to_s
        external_commit.author_login = commit.dig('author', 'name')
        external_commit.author_name = commit.dig('author', 'name')
        external_commit.url = commit['url'] ||
                              "#{repository.url}/-/commit/#{sha}"
        external_commit.branch_name = branch_name
        external_commit.committed_at = (commit['timestamp'].presence || commit['created_at'].presence)
        external_commit.last_event_at = Time.current
        external_commit.save!
        external_commit.link_issues_from_texts(commit['message'])
      end
    end

    def process_smart_commits(payload, project)
      commits = payload['commits']
      return unless commits.is_a?(Array)

      login = payload.dig('user_username') || payload.dig('user_name')
      user = RedmineDevIntegration::ProviderUserResolver.call(provider: 'gitlab', provider_login: login)

      commits.each do |commit|
        next unless commit.is_a?(Hash)
        sha = commit['id'].to_s
        message = commit['message'].to_s
        next if sha.blank? || message.blank?
        next unless message.match?(IssueKeyExtractor::ISSUE_KEY_PATTERN)

        SmartCommitService.call(
          project: project,
          commit_sha: sha,
          commit_message: message,
          user: user
        )
      end
    end

    def branch_note(branch, branch_name, payload)
      parts = ["Branch #{branch.active? ? 'created/activated' : 'deleted'}: #{branch_name}"]
      parts << "sha=#{branch.sha}" if branch.sha.present?
      parts << "ref=#{payload['ref']}" if payload['ref'].present?
      parts.join(' | ')
    end

    def branch_marker(branch, issue)
      "gitlab:branch:#{branch.id}:#{issue.id}"
    end
  end
end
