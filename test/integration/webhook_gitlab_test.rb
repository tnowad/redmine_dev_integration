# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/dev_integration_test_factory'

class WebhookGitlabTest < Redmine::IntegrationTest
  include DevIntegrationTestFactory
  include ActiveJob::TestHelper

  def setup
    Setting.stubs(:plugin_redmine_dev_integration).returns({
      'gitlab_webhook_token' => 'test_token',
      'gitlab_provider_enabled' => '1'
    })
    @project = create_project_with_prefix(name: 'gitlab_int', prefix: 'DEV')
    @issue = create_issue_with_key(project: @project, subject: 'Test')
    @repo = create_external_repository(project: @project, provider: 'gitlab', full_name: 'owner/repo', provider_repository_id: '12345')
    @original_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    clear_enqueued_jobs
  end

  def teardown
    clear_enqueued_jobs
    ActiveJob::Base.queue_adapter = @original_queue_adapter
  end

  def test_push_hook_creates_branch_and_commits
    payload = {
      object_kind: 'push',
      ref: "refs/heads/feature/#{@issue.issue_key}-login",
      before: '0000000000000000000000000000000000000000',
      after: 'abc123def456789012345678901234567890abcd',
      project: { id: 12345, web_url: 'https://gitlab.com/owner/repo' },
      commits: [
        { id: 'abc123def456789012345678901234567890abcd', message: "feat: #{@issue.issue_key} login", timestamp: '2026-01-01T00:00:00Z', author: { name: 'dev1' }, url: 'https://gitlab.com/owner/repo/-/commit/abc123def456' },
        { id: 'def456abc789012345678901234567890abcdef1', message: "chore: cleanup #{@issue.issue_key}", timestamp: '2026-01-01T00:01:00Z', author: { name: 'dev2' }, url: 'https://gitlab.com/owner/repo/-/commit/def456abc789' }
      ],
      user_username: 'dev1'
    }.to_json

    assert_difference 'ExternalBranch.count', 1 do
      assert_difference 'ExternalCommit.count', 2 do
        perform_enqueued_jobs do
          post '/dev_integrations/gitlab/webhook', headers: gitlab_headers(event: 'Push Hook', payload: payload)
        end
      end
    end

    assert_response :accepted

    branch = ExternalBranch.last
    assert_equal "feature/#{@issue.issue_key}-login", branch.name
    assert_equal 'abc123def456789012345678901234567890abcd', branch.sha
    assert_equal 'active', branch.state
    assert branch.issues.exists?(@issue.id)
  end

  def test_push_hook_creates_branch_on_new_ref_zero_before_sha
    payload = {
      object_kind: 'push',
      ref: "refs/heads/feature/#{@issue.issue_key}-auth",
      before: '0' * 40,
      after: 'abc123def456789012345678901234567890abcd',
      project: { id: 12345, web_url: 'https://gitlab.com/owner/repo' },
      commits: [
        { id: 'abc123def456789012345678901234567890abcd', message: "feat: #{@issue.issue_key} login", timestamp: '2026-01-01T00:00:00Z', author: { name: 'dev1' }, url: 'https://gitlab.com/owner/repo/-/commit/abc123def456' }
      ],
      user_username: 'dev1'
    }.to_json

    assert_difference 'ExternalBranch.count', 1 do
      assert_difference 'ExternalCommit.count', 1 do
        perform_enqueued_jobs do
          post '/dev_integrations/gitlab/webhook', headers: gitlab_headers(event: 'Push Hook', payload: payload)
        end
      end
    end

    assert_response :accepted
  end

  def test_merge_request_hook_creates_pr_record
    payload = {
      object_kind: 'merge_request',
      event_type: 'merge_request',
      user: { username: 'dev1', name: 'Dev One' },
      project: { id: 12345, web_url: 'https://gitlab.com/owner/repo' },
      object_attributes: {
        iid: 42,
        title: "Fix #{@issue.issue_key} add login",
        description: 'Implementation of login feature',
        web_url: 'https://gitlab.com/owner/repo/-/merge_requests/42',
        action: 'open',
        state: 'opened',
        source_branch: "feature/#{@issue.issue_key}-login",
        target_branch: 'main',
        last_commit: { id: 'abc123def456789012345678901234567890abcd' },
        created_at: '2026-01-01T00:00:00Z',
        updated_at: '2026-01-01T00:00:00Z'
      }
    }.to_json

    assert_difference 'ExternalPullRequest.count', 1 do
      perform_enqueued_jobs do
        post '/dev_integrations/gitlab/webhook', headers: gitlab_headers(event: 'Merge Request Hook', payload: payload)
      end
    end

    assert_response :accepted

    pr = ExternalPullRequest.last
    assert_equal 42, pr.number
    assert_equal 'gitlab', pr.provider
    assert_equal @repo, pr.external_repository
    assert_equal 'open', pr.state
    assert_equal 'dev1', pr.author_login
    assert pr.issues.exists?(@issue.id)
  end

  def test_pipeline_hook_creates_build_record
    payload = {
      object_kind: 'pipeline',
      user: { username: 'dev1', name: 'Dev One' },
      project: { id: 12345 },
      object_attributes: {
        id: 999,
        iid: 10,
        name: "CI Pipeline #{@issue.issue_key}",
        status: 'success',
        url: 'https://gitlab.com/owner/repo/-/pipelines/999',
        sha: 'abc123def456789012345678901234567890abcd',
        ref: "feature/#{@issue.issue_key}-login",
        created_at: '2026-01-01T00:00:00Z',
        finished_at: '2026-01-01T00:05:00Z',
        updated_at: '2026-01-01T00:05:00Z'
      },
      commit: {
        message: "feat: #{@issue.issue_key} login",
        title: "feat: #{@issue.issue_key} login"
      }
    }.to_json

    assert_difference 'ExternalBuild.count', 1 do
      perform_enqueued_jobs do
        post '/dev_integrations/gitlab/webhook', headers: gitlab_headers(event: 'Pipeline Hook', payload: payload)
      end
    end

    assert_response :accepted

    build = ExternalBuild.last
    assert_equal 'gitlab', build.provider
    assert_equal '999', build.provider_build_id
    assert_equal 10, build.build_number
    assert_equal 'success', build.status
    assert build.issues.exists?(@issue.id)
  end

  def test_deployment_hook_creates_deployment_record
    payload = {
      object_kind: 'deployment',
      status: 'success',
      deployment_id: 555,
      environment: 'staging',
      environment_external_url: 'https://staging.example.com',
      sha: 'abc123def456789012345678901234567890abcd',
      ref: "feature/#{@issue.issue_key}-login",
      commit_title: "Deploy #{@issue.issue_key} to staging",
      user: { username: 'dev1' },
      project: { id: 12345 },
      created_at: '2026-01-01T00:00:00Z',
      updated_at: '2026-01-01T00:05:00Z'
    }.to_json

    assert_difference 'ExternalDeployment.count', 1 do
      perform_enqueued_jobs do
        post '/dev_integrations/gitlab/webhook', headers: gitlab_headers(event: 'Deployment Hook', payload: payload)
      end
    end

    assert_response :accepted

    deployment = ExternalDeployment.last
    assert_equal 'gitlab', deployment.provider
    assert_equal '555', deployment.provider_deployment_id
    assert_equal 'staging', deployment.environment_name
    assert_equal 'success', deployment.status
    assert deployment.issues.exists?(@issue.id)
  end

  def test_returns_401_with_wrong_token
    bad_payload = { object_kind: 'push' }.to_json
    headers = gitlab_headers(event: 'Push Hook', payload: bad_payload).merge('X-Gitlab-Token' => 'wrong-token')

    assert_no_difference 'ExternalProviderEvent.count' do
      post '/dev_integrations/gitlab/webhook', headers: headers
    end

    assert_response :unauthorized
  end

  def test_event_uuid_header_used_as_delivery_id
    gitlab_event_uuid = 'uuid-abc-123-xyz'
    payload = {
      object_kind: 'push',
      ref: "refs/heads/feature/#{@issue.issue_key}-test-uuid",
      before: '0' * 40,
      after: 'abc123def456789012345678901234567890abcd',
      project: { id: 12345, web_url: 'https://gitlab.com/owner/repo' },
      commits: [
        { id: 'abc123def456789012345678901234567890abcd', message: "test: #{@issue.issue_key}", timestamp: '2026-01-01T00:00:00Z', author: { name: 'dev1' }, url: 'https://gitlab.com/owner/repo/-/commit/abc123def456' }
      ],
      user_username: 'dev1'
    }.to_json

    headers = gitlab_headers(event: 'Push Hook', payload: payload).merge(
      'X-Gitlab-Event-UUID' => gitlab_event_uuid,
      'X-Gitlab-Webhook-UUID' => 'fallback-uuid-should-not-be-used'
    )
    headers.delete('Idempotency-Key')

    assert_difference 'ExternalProviderEvent.count', 1 do
      perform_enqueued_jobs do
        post '/dev_integrations/gitlab/webhook', headers: headers
      end
    end

    assert_response :accepted
    assert_equal gitlab_event_uuid, ExternalProviderEvent.last.delivery_id
  end

  def test_returns_403_when_provider_is_disabled
    Setting.stubs(:plugin_redmine_dev_integration).returns({
      'gitlab_webhook_token' => 'test_token',
      'gitlab_provider_enabled' => '0'
    })

    payload = { object_kind: 'push' }.to_json

    assert_no_difference 'ExternalProviderEvent.count' do
      post '/dev_integrations/gitlab/webhook', headers: gitlab_headers(event: 'Push Hook', payload: payload)
    end

    assert_response :forbidden
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
