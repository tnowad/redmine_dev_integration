# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/dev_integration_test_factory'

class WebhookBuildTest < Redmine::IntegrationTest
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
    @issue = Issue.generate!(project: @project, subject: 'Test Build', author: User.find(1))
    @issue.reload
    @repo = create_external_repository(project: @project, provider: 'github', full_name: 'owner/repo', provider_repository_id: '12345')

    unless Issue.respond_to?(:find_by_issue_key)
      Issue.define_singleton_method(:find_by_issue_key) { |_key| nil }
    end
  end

  def build_headers(delivery_id: 'build-test-001')
    {
      'X-Github-Event' => 'workflow_run',
      'X-Github-Delivery' => delivery_id,
      'Content-Type' => 'application/json'
    }
  end

  def build_success_payload
    File.read(File.join(__dir__, '..', 'fixtures', 'webhook_payloads', 'github_workflow_run_success.json'))
  end

  def build_failed_payload
    File.read(File.join(__dir__, '..', 'fixtures', 'webhook_payloads', 'github_workflow_run_failed.json'))
  end

  # --- Build links to issue via branch name ---

  def test_build_links_to_issue_via_branch_name
    perform_enqueued_jobs do
      post '/dev_integrations/github/webhook',
           headers: build_headers(delivery_id: 'build-link-001'),
           params: build_success_payload
    end

    assert_response :accepted
    build = ExternalBuild.find_by(provider_build_id: '99999', provider: 'github', external_repository: @repo)
    assert build, 'Expected ExternalBuild to be created'

    if @issue.issue_key.present?
      link = ExternalBuildIssue.find_by(external_build_id: build.id, issue_id: @issue.id)
      assert link, 'Expected build linked to issue via branch name feature/DEV-1-login'
    else
      assert build, 'Build should still be created without issue_keys plugin'
    end
  end

  # --- Build record fields ---

  def test_build_created_with_correct_fields
    perform_enqueued_jobs do
      post '/dev_integrations/github/webhook',
           headers: build_headers(delivery_id: 'build-fields-001'),
           params: build_success_payload
    end

    assert_response :accepted
    build = ExternalBuild.find_by(provider_build_id: '99999', provider: 'github', external_repository: @repo)
    assert build, 'Expected ExternalBuild to exist'

    assert_equal 'success', build.status
    assert_equal 'success', build.conclusion
    assert_equal 99, build.build_number
    assert_equal 'Build and Test', build.name
    assert_equal 'https://github.com/owner/repo/actions/runs/99', build.url
    assert_equal 'abc123def456789012345678901234567890abcd', build.sha
    assert_equal 'feature/DEV-1-login', build.branch_name
    assert_equal 'dev1', build.author_login
  end

  # --- Build success triggers automation ---

  def test_build_success_triggers_automation_status_change
    target_status = IssueStatus.where.not(id: @issue.status_id).first ||
                    IssueStatus.find_by(name: 'Resolved') ||
                    IssueStatus.last
    assert target_status, 'Need a target status for automation'

    DevelopmentIntegrationProjectSetting.create!(
      project: @project,
      automation_enabled: true,
      build_success_status_id: target_status.id
    )

    perform_enqueued_jobs do
      post '/dev_integrations/github/webhook',
           headers: build_headers(delivery_id: 'build-success-auto-001'),
           params: build_success_payload
    end

    assert_response :accepted

    if @issue.issue_key.present?
      @issue.reload
      assert_equal target_status.id, @issue.status_id,
        "Expected issue status to change to #{target_status.name}, got #{@issue.status.name}"
    else
      @issue.reload
      assert_not_equal target_status.id, @issue.status_id, 'Status should not change without issue_keys'
    end
  end

  # --- Build failure adds note ---

  def test_build_failure_adds_note
    DevelopmentIntegrationProjectSetting.create!(
      project: @project,
      automation_enabled: true,
      build_failed_note_enabled: true
    )

    perform_enqueued_jobs do
      post '/dev_integrations/github/webhook',
           headers: build_headers(delivery_id: 'build-fail-note-001'),
           params: build_failed_payload
    end

    assert_response :accepted
    build = ExternalBuild.find_by(provider_build_id: '99998', provider: 'github', external_repository: @repo)
    assert build, 'Expected failed ExternalBuild to exist'
    assert_equal 'failed', build.status
    assert_equal 'failure', build.conclusion

    if @issue.issue_key.present?
      @issue.reload
      fail_journals = @issue.journals.where('notes LIKE ?', '%build_failed%')
      note_journals = @issue.journals.where('notes LIKE ?', '%Build failed%')
      all_notes = fail_journals.to_a + note_journals.to_a
      assert all_notes.any?, "Expected a journal note about build failure on issue ##{@issue.id}"
    else
      assert build, 'Build should be created even without issue_keys plugin'
    end
  end

  # --- SHA trace fallback: build links via PR SHA trace ---

  def test_build_links_via_sha_trace_from_pr
    # Create a PR with source_sha matching the build SHA but no issue key in build metadata
    pr = ExternalPullRequest.create!(
      provider: 'github',
      external_repository: @repo,
      number: 50,
      title: 'Some unrelated title',
      body: 'No issue key here',
      url: 'https://github.com/owner/repo/pull/50',
      state: 'open',
      author_login: 'dev1',
      source_branch: 'feature/no-key',
      target_branch: 'main',
      source_sha: 'abc123def456789012345678901234567890abcd',
      target_sha: 'base999base999base999base999base999ba',
      merged: false,
      opened_at: 1.day.ago,
      last_event_at: 1.day.ago
    )
    pr.issues << @issue

    # Build payload that has the same SHA but no issue key in branch/ref
    payload_json = {
      action: 'workflow_run',
      workflow_run: {
        id: 77777,
        run_number: 77,
        name: 'No Key Build',
        display_title: 'No Key Build',
        status: 'completed',
        conclusion: 'success',
        html_url: 'https://github.com/owner/repo/actions/runs/77',
        head_sha: 'abc123def456789012345678901234567890abcd',
        head_branch: 'feature/no-key',
        head_commit: { id: 'abc123def456789012345678901234567890abcd', message: 'no key here' },
        actor: { login: 'dev1' },
        run_started_at: '2026-01-01T01:00:00Z',
        created_at: '2026-01-01T01:00:00Z',
        updated_at: '2026-01-01T01:05:00Z'
      },
      repository: { id: 12345, full_name: 'owner/repo', html_url: 'https://github.com/owner/repo' },
      sender: { login: 'dev1' }
    }.to_json

    perform_enqueued_jobs do
      post '/dev_integrations/github/webhook',
           headers: build_headers(delivery_id: 'build-sha-trace-001'),
           params: payload_json
    end

    assert_response :accepted
    build = ExternalBuild.find_by(provider_build_id: '77777', provider: 'github', external_repository: @repo)
    assert build, 'Expected build to be created'

    link = ExternalBuildIssue.find_by(external_build_id: build.id, issue_id: @issue.id)
    assert link, 'Expected ExternalBuildIssue created via SHA trace (build SHA matches PR source_sha)'
  end
end
