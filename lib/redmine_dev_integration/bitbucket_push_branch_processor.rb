# frozen_string_literal: true

require 'json'

module RedmineDevIntegration
  class BitbucketPushBranchProcessor
    def initialize; end

    def call(external_provider_event)
      payload = parse_payload(external_provider_event.payload)
      return false unless payload.is_a?(Hash)
      return false unless external_provider_event.provider == 'bitbucket'
      return false unless external_provider_event.event_type == 'repo:push'

      repository = external_repository_for(payload)
      return false unless repository

      changes = payload.dig('push', 'changes')
      return false unless changes.is_a?(Array)

      handled = false

      changes.each do |change|
        branch_change = branch_change_from(change)
        next unless branch_change

        branch_name = branch_change[:name]
        branch = find_or_initialize_branch(repository, branch_name)
        branch.url = branch_url(payload, branch_name)
        branch.sha = branch_change[:sha]
        branch.state = branch_change[:deleted] ? 'deleted' : 'active'
        branch.deleted_at = Time.current if branch.deleted?
        branch.deleted_at = nil if branch.active?
        branch.save!
        commit_messages = PushCommitTextExtractor.extract(change['commits'])
        branch.link_issues_from_texts(branch_name, *commit_messages)
        process_commits(change['commits'], repository, branch_name)
        process_linked_issues(branch, branch_name, payload) if branch.active?
        process_smart_commits(change['commits'], repository.redmine_project, payload)
        handled = true
      end

      handled
    end

    private

    def parse_payload(payload)
      return payload if payload.is_a?(Hash)
      return {} if payload.blank?

      JSON.parse(payload)
    rescue JSON::ParserError
      nil
    end

    def branch_change_from(change)
      new_ref = change['new']
      old_ref = change['old']

      ref = new_ref || old_ref
      return unless ref.is_a?(Hash) && ref['type'] == 'branch'

      deleted = new_ref.nil? && old_ref.present?

      {
        name: ref['name'],
        sha: new_ref.dig('target', 'hash').presence,
        deleted: deleted
      }
    end

    def external_repository_for(payload)
      RedmineDevIntegration::ExternalRepositoryResolver.bitbucket(payload)
    end

    def find_or_initialize_branch(repository, branch_name)
      ExternalBranch.find_or_initialize_by(external_repository: repository, name: branch_name)
    end

    def branch_url(payload, branch_name)
      html_url = payload.dig('repository', 'links', 'html', 'href').to_s
      return if html_url.blank?

      "#{html_url}/src/#{branch_name}"
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
        sha = commit['hash'].to_s
        next if sha.blank?

        external_commit = ExternalCommit.find_or_initialize_by(
          provider: 'bitbucket',
          external_repository: repository,
          provider_commit_id: sha
        )
        external_commit.sha = sha
        external_commit.short_sha = sha[0, 7]
        external_commit.message = commit['message'].to_s
        external_commit.author_login = commit.dig('author', 'user', 'username') || commit.dig('author', 'raw')
        external_commit.author_name = commit.dig('author', 'user', 'display_name') || commit.dig('author', 'raw')
        external_commit.url = commit.dig('links', 'html', 'href') ||
                              "#{repository.url}/commits/#{sha}"
        external_commit.branch_name = branch_name
        external_commit.committed_at = commit['date'].presence
        external_commit.last_event_at = Time.current
        external_commit.save!
        external_commit.link_issues_from_texts(commit['message'])
      end
    end

    def process_smart_commits(commits, project, payload)
      return unless commits.is_a?(Array)

      login = payload.dig('actor', 'username')
      user = RedmineDevIntegration::ProviderUserResolver.call(provider: 'bitbucket', provider_login: login)

      commits.each do |commit|
        next unless commit.is_a?(Hash)
        sha = commit['hash'].to_s
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
      parts.join(' | ')
    end

    def branch_marker(branch, issue)
      "bitbucket:branch:#{branch.id}:#{issue.id}"
    end
  end
end
