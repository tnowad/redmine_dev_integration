# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/dev_integration_test_factory'

class WebhookPrTest < Redmine::IntegrationTest
  include DevIntegrationTestFactory
  include ActiveJob::TestHelper

  def setup
    RedmineDevIntegration::GitHubWebhookSignatureVerifier.any_instance.stubs(:valid?).returns(true)
    Setting.stubs(:plugin_redmine_dev_integration).returns({
      'github_webhook_secret' => 'test_secret',
      'github_provider_enabled' => '1'
    })
    @project = Project.generate!
    @project.update_column(:issue_key_prefix, 'DEV')
    @issue = Issue.generate!(project: @project, subject: 'Test PR', author: User.find(1))
    @issue.reload
    @repo = create_external_repository(project: @project, provider: 'github', full_name: 'owner/repo', provider_repository_id: '12345')

    unless Issue.respond_to?(:find_by_issue_key)
      Issue.define_singleton_method(:find_by_issue_key) { |_key| nil }
    end
  end

  def pr_headers(delivery_id: 'pr-test-001')
    {
      'X-GitHub-Event' => 'pull_request',
      'X-GitHub-Delivery' => delivery_id,
      'Content-Type' => 'application/json'
    }
  end

  def pr_opened_payload
    File.read(File.join(__dir__, '..', 'fixtures', 'webhook_payloads', 'github_pr_opened.json'))
  end

  def pr_closed_merged_payload
    File.read(File.join(__dir__, '..', 'fixtures', 'webhook_payloads', 'github_pr_closed_merged.json'))
  end

  # --- PR opened ---

  def test_pr_opened_creates_pull_request_record
    perform_enqueued_jobs do
      post '/dev_integrations/github/webhook',
           headers: pr_headers(delivery_id: 'pr-opened-001'),
           params: pr_opened_payload
    end

    assert_response :accepted
    pr = ExternalPullRequest.find_by(number: 42, provider: 'github', external_repository: @repo)
    assert pr, 'Expected ExternalPullRequest to be created'
    assert_equal 'Fix DEV-1 add login feature', pr.title
    assert_equal 'This PR implements the login feature for DEV-1', pr.body
    assert_equal 'https://github.com/owner/repo/pull/42', pr.url
    assert_equal 'open', pr.state
    assert_equal 'dev1', pr.author_login
    assert_equal 'feature/DEV-1-login', pr.source_branch
    assert_equal 'main', pr.target_branch
    assert_equal 'abc123def456789012345678901234567890abcd', pr.source_sha
    assert_equal 'base999base999base999base999base999ba', pr.target_sha
    assert_equal false, pr.merged
    assert_not_nil pr.opened_at
    assert_nil pr.closed_at
    assert_nil pr.merged_at
  end

  def test_pr_linked_to_issue_via_title
    perform_enqueued_jobs do
      post '/dev_integrations/github/webhook',
           headers: pr_headers(delivery_id: 'pr-link-title-001'),
           params: pr_opened_payload
    end

    assert_response :accepted
    pr = ExternalPullRequest.find_by(number: 42, provider: 'github', external_repository: @repo)

    if @issue.issue_key.present?
      link = ExternalPullRequestIssue.find_by(external_pull_request_id: pr.id, issue_id: @issue.id)
      assert link, 'Expected PR linked to issue via title containing DEV-1'
    else
      assert pr, 'PR should still be created without issue_keys plugin'
    end
  end

  def test_pr_linked_to_issue_via_source_branch
    perform_enqueued_jobs do
      post '/dev_integrations/github/webhook',
           headers: pr_headers(delivery_id: 'pr-link-branch-001'),
           params: pr_opened_payload
    end

    assert_response :accepted
    pr = ExternalPullRequest.find_by(number: 42, provider: 'github', external_repository: @repo)

    if @issue.issue_key.present?
      link = ExternalPullRequestIssue.find_by(external_pull_request_id: pr.id, issue_id: @issue.id)
      assert link, 'Expected PR linked to issue via source_branch containing DEV-1'
    else
      assert pr, 'PR should still be created without issue_keys plugin'
    end
  end

  # --- PR opened automation ---

  def test_pr_opened_triggers_automation_status_change
    status = IssueStatus.find_by(name: 'In Progress') || IssueStatus.first
    target_status = IssueStatus.where.not(id: @issue.status_id).first ||
                    IssueStatus.find_by(name: 'Resolved') ||
                    IssueStatus.last
    assert target_status, 'Need a target status for automation'

    DevelopmentIntegrationProjectSetting.create!(
      project: @project,
      automation_enabled: true,
      pr_opened_status_id: target_status.id
    )

    perform_enqueued_jobs do
      post '/dev_integrations/github/webhook',
           headers: pr_headers(delivery_id: 'pr-open-auto-001'),
           params: pr_opened_payload
    end

    assert_response :accepted
    @issue.reload

    if @issue.issue_key.present?
      assert_equal target_status.id, @issue.status_id,
        "Expected issue status ##{@issue.status_id} to change to #{target_status.name}"
    else
      assert_not_equal target_status.id, @issue.status_id, 'Status should not change without issue_keys'
    end
  end

  # --- PR merged ---

  def test_pr_merged_triggers_pr_merged_status_automation
    resolved_status = IssueStatus.find_by(name: 'Resolved') || IssueStatus.last
    closed_status = IssueStatus.find_by(name: 'Closed') || IssueStatus.last
    target_status = IssueStatus.where.not(id: @issue.status_id).first || resolved_status
    assert target_status, 'Need a target status for PR merged automation'

    DevelopmentIntegrationProjectSetting.create!(
      project: @project,
      automation_enabled: true,
      pr_merged_status_id: target_status.id
    )

    perform_enqueued_jobs do
      post '/dev_integrations/github/webhook',
           headers: pr_headers(delivery_id: 'pr-merged-auto-001'),
           params: pr_closed_merged_payload
    end

    assert_response :accepted
    pr = ExternalPullRequest.find_by(number: 42, provider: 'github', external_repository: @repo)
    assert pr, 'Expected PR to exist'
    assert_equal 'closed', pr.state
    assert_equal true, pr.merged
    assert_not_nil pr.merged_at
    assert_not_nil pr.closed_at

    @issue.reload
    if @issue.issue_key.present?
      assert_equal target_status.id, @issue.status_id,
        "Expected issue status to change to #{target_status.name}, got #{@issue.status.name}"
    else
      assert_not_equal target_status.id, @issue.status_id, 'Status should not change without issue_keys'
    end
  end

  # --- PR closed without merge ---

  def test_pr_closed_without_merge_adds_journal_note
    note_status = IssueStatus.find_by(name: 'Rejected') || IssueStatus.last

    DevelopmentIntegrationProjectSetting.create!(
      project: @project,
      automation_enabled: true,
      pr_closed_note_enabled: true
    )

    payload_json = {
      action: 'closed',
      number: 43,
      pull_request: {
        id: 1000,
        number: 43,
        title: 'Fix DEV-1 refactor only',
        body: 'Just a refactor for DEV-1',
        state: 'closed',
        html_url: 'https://github.com/owner/repo/pull/43',
        user: { login: 'dev1', id: 100 },
        head: { ref: 'feature/DEV-1-refactor', sha: 'abc123def456789012345678901234567890abcd' },
        base: { ref: 'main', sha: 'base999base999base999base999base999ba' },
        merged: false,
        merge_commit_sha: nil,
        created_at: '2026-01-01T00:00:00Z',
        updated_at: '2026-01-01T03:00:00Z',
        closed_at: '2026-01-01T03:00:00Z'
      },
      repository: { id: 12345, full_name: 'owner/repo', html_url: 'https://github.com/owner/repo' },
      sender: { login: 'dev1' }
    }.to_json

    perform_enqueued_jobs do
      post '/dev_integrations/github/webhook',
           headers: pr_headers(delivery_id: 'pr-closed-note-001'),
           params: payload_json
    end

    assert_response :accepted
    pr = ExternalPullRequest.find_by(number: 43, provider: 'github', external_repository: @repo)
    assert pr, 'Expected PR #43 to be created'
    assert_equal 'closed', pr.state
    assert_equal false, pr.merged

    if @issue.issue_key.present?
      @issue.reload
      audit_journals = @issue.journals.where('notes LIKE ?', '%pr_closed_without_merge%').to_a
      pr_journals = @issue.journals.where('notes LIKE ?', "%##{pr.number}%").to_a
      note_journals = audit_journals + pr_journals
      assert note_journals.any?, "Expected a journal note for closed-without-merge PR on issue ##{@issue.id}"
    else
      assert pr, 'PR should be created even without issue_keys plugin'
    end
  end

  # --- PR timestamps ---

  def test_pr_timestamps_merged_at_opened_at_closed_at_set
    perform_enqueued_jobs do
      post '/dev_integrations/github/webhook',
           headers: pr_headers(delivery_id: 'pr-ts-001'),
           params: pr_closed_merged_payload
    end

    assert_response :accepted
    pr = ExternalPullRequest.find_by(number: 42, provider: 'github', external_repository: @repo)
    assert pr, 'Expected PR to exist'

    assert_not_nil pr.opened_at
    assert_not_nil pr.closed_at
    assert_not_nil pr.merged_at
    assert_equal Time.zone.parse('2026-01-01T00:00:00Z'), pr.opened_at
    assert_equal Time.zone.parse('2026-01-01T02:00:00Z'), pr.closed_at
    assert_equal Time.zone.parse('2026-01-01T02:00:00Z'), pr.merged_at
  end
end
