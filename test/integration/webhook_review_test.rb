# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/dev_integration_test_factory'

class WebhookReviewTest < Redmine::IntegrationTest
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
    @issue = Issue.generate!(project: @project, subject: 'Test Review', author: User.find(1))
    @issue.reload
    @repo = create_external_repository(project: @project, provider: 'github', full_name: 'owner/repo', provider_repository_id: '12345')

    unless Issue.respond_to?(:find_by_issue_key)
      Issue.define_singleton_method(:find_by_issue_key) { |_key| nil }
    end
  end

  def review_headers(delivery_id: 'review-test-001')
    {
      'X-GitHub-Event' => 'pull_request_review',
      'X-GitHub-Delivery' => delivery_id,
      'Content-Type' => 'application/json'
    }
  end

  def test_pull_request_review_approved_creates_external_review
    ExternalPullRequest.create!(
      provider: 'github',
      external_repository: @repo,
      number: 42,
      title: "Fix #{@issue.issue_key} login",
      body: 'Implementation',
      url: 'https://github.com/owner/repo/pull/42',
      state: 'open',
      author_login: 'author1',
      source_branch: 'feature/login',
      target_branch: 'main',
      merged: false
    )

    payload = {
      action: 'submitted',
      review: {
        id: 888,
        user: { login: 'reviewer1', id: 200 },
        body: 'LGTM!',
        state: 'approved',
        submitted_at: '2026-01-15T10:00:00Z'
      },
      pull_request: {
        id: 1000,
        number: 42,
        title: 'Fix DEV-1 login',
        state: 'open',
        html_url: 'https://github.com/owner/repo/pull/42',
        user: { login: 'author1' },
        head: { ref: 'feature/login', sha: 'abc123' },
        base: { ref: 'main', sha: 'base999' }
      },
      repository: {
        id: 12345,
        full_name: 'owner/repo',
        html_url: 'https://github.com/owner/repo'
      },
      sender: { login: 'reviewer1' }
    }.to_json

    assert_difference 'ExternalReview.count', 1 do
      perform_enqueued_jobs do
        post '/dev_integrations/github/webhook',
             headers: review_headers(delivery_id: 'review-approved-001'),
             params: payload
      end
    end

    assert_response :accepted

    review = ExternalReview.last
    assert_equal 'github', review.provider
    assert_equal '888', review.provider_review_id
    assert_equal 'reviewer1', review.reviewer_login
    assert_equal 'APPROVED', review.state
    assert_equal 'LGTM!', review.body
    assert_equal Time.zone.parse('2026-01-15T10:00:00Z'), review.submitted_at
  end

  def test_pull_request_review_changes_requested_updates_via_pr
    pr = ExternalPullRequest.create!(
      provider: 'github',
      external_repository: @repo,
      number: 43,
      title: "Update #{@issue.issue_key} auth",
      body: 'Auth update',
      url: 'https://github.com/owner/repo/pull/43',
      state: 'open',
      author_login: 'author1',
      source_branch: 'feature/auth',
      target_branch: 'main',
      merged: false
    )

    ExternalReview.create!(
      provider: 'github',
      external_pull_request: pr,
      provider_review_id: '999',
      reviewer_login: 'reviewer1',
      state: 'APPROVED',
      submitted_at: 1.hour.ago
    )

    payload = {
      action: 'submitted',
      review: {
        id: 999,
        user: { login: 'reviewer1' },
        body: 'Please fix the auth middleware',
        state: 'changes_requested',
        submitted_at: '2026-01-15T11:00:00Z'
      },
      pull_request: {
        id: 1001,
        number: 43,
        title: 'Update DEV-1 auth',
        state: 'open',
        html_url: 'https://github.com/owner/repo/pull/43',
        user: { login: 'author1' },
        head: { ref: 'feature/auth', sha: 'abc124' },
        base: { ref: 'main', sha: 'base999' }
      },
      repository: {
        id: 12345,
        full_name: 'owner/repo',
        html_url: 'https://github.com/owner/repo'
      },
      sender: { login: 'reviewer1' }
    }.to_json

    assert_no_difference 'ExternalReview.count' do
      perform_enqueued_jobs do
        post '/dev_integrations/github/webhook',
             headers: review_headers(delivery_id: 'review-changes-001'),
             params: payload
      end
    end

    assert_response :accepted

    review = ExternalReview.find_by!(provider_review_id: '999')
    assert_equal 'CHANGES_REQUESTED', review.state
    assert_equal 'Please fix the auth middleware', review.body
    assert_equal Time.zone.parse('2026-01-15T11:00:00Z'), review.submitted_at
  end

  def test_pull_request_review_no_matching_pr_returns_accepted
    payload = {
      action: 'submitted',
      review: {
        id: 888,
        user: { login: 'reviewer1' },
        body: 'LGTM!',
        state: 'approved',
        submitted_at: '2026-01-15T10:00:00Z'
      },
      pull_request: {
        id: 1000,
        number: 9999,
        title: 'Unknown PR',
        state: 'open',
        html_url: 'https://github.com/owner/repo/pull/9999',
        user: { login: 'author1' },
        head: { ref: 'feature/unknown', sha: 'abc123' },
        base: { ref: 'main', sha: 'base999' }
      },
      repository: {
        id: 12345,
        full_name: 'owner/repo',
        html_url: 'https://github.com/owner/repo'
      },
      sender: { login: 'reviewer1' }
    }.to_json

    assert_no_difference 'ExternalReview.count' do
      perform_enqueued_jobs do
        post '/dev_integrations/github/webhook',
             headers: review_headers(delivery_id: 'review-no-pr-001'),
             params: payload
      end
    end

    assert_response :accepted
  end

  def test_gitlab_merge_request_approval_creates_review
    Setting.unstub(:plugin_redmine_dev_integration)
    Setting.stubs(:plugin_redmine_dev_integration).returns({
      'gitlab_webhook_token' => 'test_token',
      'gitlab_provider_enabled' => '1'
    })
    RedmineDevIntegration::GitlabWebhookTokenVerifier.any_instance.stubs(:valid?).returns(true)
    project = create_project_with_prefix(name: 'gitlab_review', prefix: 'GL')
    issue = create_issue_with_key(project: project, subject: 'GitLab MR approval test')
    repo = create_external_repository(project: project, provider: 'gitlab', full_name: 'owner/repo', provider_repository_id: '99999')

    pr = ExternalPullRequest.create!(
      provider: 'gitlab',
      external_repository: repo,
      number: 10,
      title: "MR #{issue.issue_key}",
      url: 'https://gitlab.com/owner/repo/-/merge_requests/10',
      state: 'open',
      author_login: 'dev1',
      source_branch: 'feature/auth',
      target_branch: 'main',
      merged: false
    )
    pr.issues << issue

    payload = {
      object_kind: 'merge_request',
      event_type: 'merge_request',
      user: { username: 'reviewer1', name: 'Reviewer One' },
      project: { id: 99999, web_url: 'https://gitlab.com/owner/repo' },
      object_attributes: {
        iid: 10,
        id: 100,
        title: "MR #{issue.issue_key}",
        description: 'Auth fix',
        web_url: 'https://gitlab.com/owner/repo/-/merge_requests/10',
        action: 'approved',
        state: 'opened',
        source_branch: 'feature/auth',
        target_branch: 'main',
        last_commit: { id: 'abc123def456789012345678901234567890abcd' },
        created_at: '2026-01-15T10:00:00Z',
        updated_at: '2026-01-15T11:00:00Z'
      }
    }.to_json

    assert_difference 'ExternalReview.count', 1 do
      perform_enqueued_jobs do
        post '/dev_integrations/gitlab/webhook', headers: gitlab_headers(event: 'Merge Request Hook', payload: payload)
      end
    end

    assert_response :accepted

    review = ExternalReview.last
    assert_equal 'gitlab', review.provider
    assert_equal pr.id, review.external_pull_request_id
    assert_equal 'reviewer1', review.reviewer_login
    assert_equal 'Reviewer One', review.reviewer_name
    assert_equal 'APPROVED', review.state
  end

  private

  def gitlab_headers(event:, payload:)
    {
      'RAW_POST_DATA' => payload,
      'CONTENT_TYPE' => 'application/json',
      'X-Gitlab-Event' => event,
      'X-Gitlab-Token' => 'test_token',
      'Idempotency-Key' => "idempotent-#{SecureRandom.hex(8)}"
    }
  end
end
