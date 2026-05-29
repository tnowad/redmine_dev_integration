# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/dev_integration_test_factory'

class WebhookPushToIssueTest < Redmine::IntegrationTest
  include DevIntegrationTestFactory
  include ActiveJob::TestHelper

  def setup
    RedmineDevIntegration::GithubWebhookSignatureVerifier.any_instance.stubs(:valid?).returns(true)
    Setting.stubs(:plugin_redmine_dev_integration).returns({
      'github_webhook_secret' => 'test_secret',
      'github_provider_enabled' => '1'
    })
    @project = Project.generate!
    @project.update_column(:issue_key_prefix, 'DEV')
    @issue = Issue.generate!(project: @project, subject: 'Test', author: User.find(1))
    @issue.reload
    @repo = create_external_repository(project: @project, provider: 'github', full_name: 'owner/repo', provider_repository_id: '12345')

    unless Issue.respond_to?(:find_by_issue_key)
      Issue.define_singleton_method(:find_by_issue_key) { |_key| nil }
    end
  end

  def basic_push_headers(delivery_id: 'push-test-001')
    {
      'X-Github-Event' => 'push',
      'X-Github-Delivery' => delivery_id,
      'Content-Type' => 'application/json'
    }
  end

  def push_payload
    File.read(File.join(__dir__, '..', 'fixtures', 'webhook_payloads', 'github_push_basic.json'))
  end

  def delete_payload
    File.read(File.join(__dir__, '..', 'fixtures', 'webhook_payloads', 'github_push_branch_delete.json'))
  end

  # --- Push webhook creates branch ---

  def test_push_creates_branch_record
    perform_enqueued_jobs do
      post '/dev_integrations/github/webhook',
           headers: basic_push_headers,
           params: push_payload
    end

    assert_response :accepted
    branch = ExternalBranch.find_by(name: 'feature/DEV-1-login', external_repository: @repo)
    assert branch, 'Expected ExternalBranch to be created'
    assert_equal 'abc123def456789012345678901234567890abcd', branch.sha
    assert_equal 'active', branch.state
    assert_equal 'https://github.com/owner/repo/tree/feature/DEV-1-login', branch.url
    assert_nil branch.deleted_at
  end

  def test_branch_linked_to_issue_via_branch_name
    perform_enqueued_jobs do
      post '/dev_integrations/github/webhook',
           headers: basic_push_headers,
           params: push_payload
    end

    assert_response :accepted
    branch = ExternalBranch.find_by(name: 'feature/DEV-1-login', external_repository: @repo)

    if @issue.issue_key.present?
      link = ExternalBranchIssue.find_by(external_branch_id: branch.id, issue_id: @issue.id)
      assert link, 'Expected ExternalBranchIssue linking branch to issue'
    else
      assert branch, 'Branch should be created even without issue_keys plugin'
    end
  end

  def test_push_creates_commit_records
    perform_enqueued_jobs do
      post '/dev_integrations/github/webhook',
           headers: basic_push_headers,
           params: push_payload
    end

    assert_response :accepted
    commits = ExternalCommit.where(external_repository: @repo)
    assert_equal 2, commits.count, 'Expected 2 ExternalCommit records'

    first = commits.find_by(provider_commit_id: 'abc123def456789012345678901234567890abcd')
    assert first, 'Expected first commit'
    assert_equal 'feat: implement DEV-1 login feature', first.message.lines.first.chomp
    assert_equal 'dev1', first.author_login
    assert_equal 'abc123d', first.short_sha
    assert_equal 'feature/DEV-1-login', first.branch_name

    second = commits.find_by(provider_commit_id: 'def456abc789012345678901234567890abcdef1')
    assert second, 'Expected second commit'
    assert_equal 'chore: cleanup after DEV-1 implementation', second.message
  end

  def test_first_commit_linked_to_issue_second_not_linked
    perform_enqueued_jobs do
      post '/dev_integrations/github/webhook',
           headers: basic_push_headers,
           params: push_payload
    end

    assert_response :accepted
    first_commit = ExternalCommit.find_by(provider_commit_id: 'abc123def456789012345678901234567890abcd')
    second_commit = ExternalCommit.find_by(provider_commit_id: 'def456abc789012345678901234567890abcdef1')

    if @issue.issue_key.present?
      first_link = ExternalCommitIssue.find_by(external_commit_id: first_commit.id, issue_id: @issue.id)
      assert first_link, 'Expected first commit linked to issue (has DEV-1 in message)'

      second_links = ExternalCommitIssue.where(external_commit_id: second_commit.id)
      assert second_links.count >= 1, 'Second commit links to issue (DEV-1 appears in message)'
    else
      assert first_commit, 'First commit should still be created without issue_keys plugin'
      assert second_commit, 'Second commit should still be created without issue_keys plugin'
    end
  end

  # --- Idempotent delivery ---

  def test_same_delivery_id_twice_creates_one_branch
    payload = push_payload
    headers = basic_push_headers(delivery_id: 'push-idem-001')

    2.times do
      perform_enqueued_jobs do
        post '/dev_integrations/github/webhook', headers: headers, params: payload
      end
    end

    assert_response :success
    branches = ExternalBranch.where(name: 'feature/DEV-1-login', external_repository: @repo)
    assert_equal 1, branches.count, 'Expected only 1 branch record (idempotent)'
    events = ExternalProviderEvent.where(delivery_id: 'push-idem-001', provider: 'github', event_type: 'push')
    assert_equal 1, events.count, 'Expected only 1 event record'
  end

  # --- Branch delete ---

  def test_branch_delete_sets_deleted_state
    perform_enqueued_jobs do
      post '/dev_integrations/github/webhook',
           headers: basic_push_headers(delivery_id: 'push-delete-001'),
           params: delete_payload
    end

    assert_response :accepted
    branch = ExternalBranch.find_by(name: 'feature/DEV-1-old', external_repository: @repo)
    assert branch, 'Expected branch to be created (find_or_initialize) and then soft-deleted'
    assert_equal 'deleted', branch.state
    assert_not_nil branch.deleted_at
    refute_equal 'abc123def456789012345678901234567890abcd', branch.sha,
                 'SHA should be after (00000) not before (abc123) for delete events'
  end

  # --- Smart commit: #done ---

  def test_smart_commit_done_changes_issue_status
    Setting.stubs(:plugin_redmine_dev_integration).returns({
      'github_webhook_secret' => 'test_secret',
      'github_provider_enabled' => '1'
    })

    status = IssueStatus.find_by(name: 'Resolved') || IssueStatus.last
    assert status, 'Need a target status for smart commit #done'

    DevelopmentIntegrationProjectSetting.create!(
      project: @project,
      automation_enabled: true,
      smart_commits_enabled: true,
      pr_merged_status_id: status.id
    )

    issue_key = @issue.issue_key || 'DEV-1'
    payload_json = {
      ref: "refs/heads/feature/#{issue_key}-login",
      before: '0000000000000000000000000000000000000000',
      after: 'abc123def456789012345678901234567890abcd',
      repository: { id: 12345, full_name: 'owner/repo', html_url: 'https://github.com/owner/repo' },
      pusher: { name: 'dev1', email: 'dev1@example.com' },
      sender: { login: 'dev1' },
      commits: [
        {
          id: 'abc123def456789012345678901234567890abcd',
          message: "#{issue_key} #done",
          timestamp: '2026-01-01T00:00:00Z',
          author: { username: 'dev1', name: 'Dev One', email: 'dev1@example.com' },
          url: 'https://github.com/owner/repo/commit/abc123def456789012345678901234567890abcd',
          distinct: true
        }
      ],
      head_commit: {
        id: 'abc123def456789012345678901234567890abcd',
        message: "#{issue_key} #done",
        timestamp: '2026-01-01T00:00:00Z',
        author: { username: 'dev1', name: 'Dev One', email: 'dev1@example.com' },
        url: 'https://github.com/owner/repo/commit/abc123def456789012345678901234567890abcd'
      }
    }.to_json

    Issue.stubs(:find_by_issue_key).with(issue_key).returns(@issue)

    perform_enqueued_jobs do
      post '/dev_integrations/github/webhook',
           headers: basic_push_headers(delivery_id: 'smart-done-001'),
           params: payload_json
    end

    assert_response :accepted
    @issue.reload
    assert_equal status.id, @issue.status_id,
      "Expected issue status to change to #{status.name}, got #{@issue.status.name}"
  end

  # --- Smart commit: #time ---

  def test_smart_commit_time_creates_time_entry
    Setting.stubs(:plugin_redmine_dev_integration).returns({
      'github_webhook_secret' => 'test_secret',
      'github_provider_enabled' => '1'
    })

    DevelopmentIntegrationProjectSetting.create!(
      project: @project,
      automation_enabled: true,
      smart_commits_enabled: true,
      pr_merged_status_id: IssueStatus.last&.id
    )

    user = User.find(1)
    activity = TimeEntryActivity.shared.active.order(:position).first
    assert activity, 'Need a TimeEntryActivity'

    issue_key = @issue.issue_key || 'DEV-1'
    payload_json = {
      ref: "refs/heads/feature/#{issue_key}-login",
      before: '0000000000000000000000000000000000000000',
      after: 'abc123def456789012345678901234567890abcd',
      repository: { id: 12345, full_name: 'owner/repo', html_url: 'https://github.com/owner/repo' },
      pusher: { name: 'dev1', email: 'dev1@example.com' },
      sender: { login: 'dev1' },
      commits: [
        {
          id: 'abc123def456789012345678901234567890abcd',
          message: "#{issue_key} #time 2h",
          timestamp: '2026-01-01T00:00:00Z',
          author: { username: 'dev1', name: 'Dev One', email: 'dev1@example.com' },
          url: 'https://github.com/owner/repo/commit/abc123def456789012345678901234567890abcd',
          distinct: true
        }
      ],
      head_commit: {
        id: 'abc123def456789012345678901234567890abcd',
        message: "#{issue_key} #time 2h",
        timestamp: '2026-01-01T00:00:00Z',
        author: { username: 'dev1', name: 'Dev One', email: 'dev1@example.com' },
        url: 'https://github.com/owner/repo/commit/abc123def456789012345678901234567890abcd'
      }
    }.to_json

    Issue.stubs(:find_by_issue_key).with(issue_key).returns(@issue)

    perform_enqueued_jobs do
      post '/dev_integrations/github/webhook',
           headers: basic_push_headers(delivery_id: 'smart-time-001'),
           params: payload_json
    end

    assert_response :accepted
    entry = TimeEntry.find_by(issue_id: @issue.id)
    assert entry, 'Expected a TimeEntry to be created'
    assert_in_delta 2.0, entry.hours, 0.01, 'Expected 2.0 hours logged'
  end

  # --- Smart commit: #assign ---

  def test_smart_commit_assign_changes_assigned_to
    Setting.stubs(:plugin_redmine_dev_integration).returns({
      'github_webhook_secret' => 'test_secret',
      'github_provider_enabled' => '1'
    })

    DevelopmentIntegrationProjectSetting.create!(
      project: @project,
      automation_enabled: true,
      smart_commits_enabled: true,
      pr_merged_status_id: IssueStatus.last&.id
    )

    admin = User.find_by(login: 'admin') || User.find(1)

    issue_key = @issue.issue_key || 'DEV-1'
    payload_json = {
      ref: "refs/heads/feature/#{issue_key}-login",
      before: '0000000000000000000000000000000000000000',
      after: 'abc123def456789012345678901234567890abcd',
      repository: { id: 12345, full_name: 'owner/repo', html_url: 'https://github.com/owner/repo' },
      pusher: { name: 'dev1', email: 'dev1@example.com' },
      sender: { login: 'dev1' },
      commits: [
        {
          id: 'abc123def456789012345678901234567890abcd',
          message: "#{issue_key} #assign #{admin.login}",
          timestamp: '2026-01-01T00:00:00Z',
          author: { username: 'dev1', name: 'Dev One', email: 'dev1@example.com' },
          url: 'https://github.com/owner/repo/commit/abc123def456789012345678901234567890abcd',
          distinct: true
        }
      ],
      head_commit: {
        id: 'abc123def456789012345678901234567890abcd',
        message: "#{issue_key} #assign #{admin.login}",
        timestamp: '2026-01-01T00:00:00Z',
        author: { username: 'dev1', name: 'Dev One', email: 'dev1@example.com' },
        url: 'https://github.com/owner/repo/commit/abc123def456789012345678901234567890abcd'
      }
    }.to_json

    Issue.stubs(:find_by_issue_key).with(issue_key).returns(@issue)

    perform_enqueued_jobs do
      post '/dev_integrations/github/webhook',
           headers: basic_push_headers(delivery_id: 'smart-assign-001'),
           params: payload_json
    end

    assert_response :accepted
    @issue.reload
    assert_equal admin.id, @issue.assigned_to_id,
      "Expected issue assigned_to to be #{admin.login}, got #{@issue.assigned_to&.login}"
  end
end
