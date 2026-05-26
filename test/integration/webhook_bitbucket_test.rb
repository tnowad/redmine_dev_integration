# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/dev_integration_test_factory'

class WebhookBitbucketTest < Redmine::IntegrationTest
  include DevIntegrationTestFactory
  include ActiveJob::TestHelper

  def setup
    Setting.stubs(:plugin_redmine_dev_integration).returns({
      'bitbucket_webhook_secret' => 'test_secret',
      'bitbucket_provider_enabled' => '1'
    })
    @project = create_project_with_prefix(name: 'bitbucket_int', prefix: 'DEV')
    @issue = create_issue_with_key(project: @project, subject: 'Test')
    @repo = create_external_repository(project: @project, provider: 'bitbucket', full_name: 'owner/repo', provider_repository_id: 'abc-def-123')
    @original_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    clear_enqueued_jobs
  end

  def teardown
    clear_enqueued_jobs
    ActiveJob::Base.queue_adapter = @original_queue_adapter
  end

  def test_repo_push_creates_branch_and_commits
    payload = {
      push: {
        changes: [
          {
            new: { type: 'branch', name: "feature/#{@issue.issue_key}-login", target: { hash: 'abc123def456789012345678901234567890abcd' } },
            old: { type: 'branch', name: "feature/#{@issue.issue_key}-login" },
            commits: [
              { hash: 'abc123def456789012345678901234567890abcd', message: "feat: #{@issue.issue_key} login", date: '2026-01-01T00:00:00Z', author: { user: { username: 'dev1', display_name: 'Dev One' }, raw: 'Dev One <dev1@test.com>' }, links: { html: { href: 'https://bitbucket.org/owner/repo/commits/abc123def456' } } }
            ]
          }
        ]
      },
      repository: { full_name: 'owner/repo', uuid: 'abc-def-123', links: { html: { href: 'https://bitbucket.org/owner/repo' } } },
      actor: { username: 'dev1' }
    }.to_json

    assert_difference 'ExternalBranch.count', 1 do
      assert_difference 'ExternalCommit.count', 1 do
        perform_enqueued_jobs do
          post '/dev_integrations/bitbucket/webhook',
               headers: bitbucket_headers(event: 'repo:push', payload: payload)
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

  def test_repo_push_handles_multiple_changes
    payload = {
      push: {
        changes: [
          {
            new: { type: 'branch', name: "feature/#{@issue.issue_key}-a", target: { hash: 'aaa111bbb222' } },
            old: { type: 'branch', name: "feature/#{@issue.issue_key}-a" },
            commits: [
              { hash: 'aaa111bbb222', message: "feat: #{@issue.issue_key} part a", date: '2026-01-01T00:00:00Z', author: { user: { username: 'dev1', display_name: 'Dev One' }, raw: 'Dev One <dev1@test.com>' }, links: { html: { href: 'https://bitbucket.org/owner/repo/commits/aaa111bbb222' } } }
            ]
          },
          {
            new: { type: 'branch', name: "feature/#{@issue.issue_key}-b", target: { hash: 'ccc333ddd444' } },
            old: { type: 'branch', name: "feature/#{@issue.issue_key}-b" },
            commits: [
              { hash: 'ccc333ddd444', message: "chore: #{@issue.issue_key} part b", date: '2026-01-01T00:01:00Z', author: { user: { username: 'dev2', display_name: 'Dev Two' }, raw: 'Dev Two <dev2@test.com>' }, links: { html: { href: 'https://bitbucket.org/owner/repo/commits/ccc333ddd444' } } }
            ]
          }
        ]
      },
      repository: { full_name: 'owner/repo', uuid: 'abc-def-123', links: { html: { href: 'https://bitbucket.org/owner/repo' } } },
      actor: { username: 'dev1' }
    }.to_json

    assert_difference 'ExternalBranch.count', 2 do
      perform_enqueued_jobs do
        post '/dev_integrations/bitbucket/webhook',
             headers: bitbucket_headers(event: 'repo:push', payload: payload)
      end
    end

    assert_response :accepted
  end

  def test_pullrequest_created_creates_pr_record
    payload = {
      pullrequest: {
        id: 42,
        title: "Fix #{@issue.issue_key} add login",
        description: 'Implementation of login feature',
        state: 'OPEN',
        author: { username: 'dev1', display_name: 'Dev One' },
        source: { branch: { name: "feature/#{@issue.issue_key}-login" }, commit: { hash: 'abc123def456789012345678901234567890abcd' } },
        destination: { branch: { name: 'main' }, commit: { hash: 'base999base999' } },
        created_on: '2026-01-01T00:00:00Z',
        updated_on: '2026-01-01T00:00:00Z',
        links: { html: { href: 'https://bitbucket.org/owner/repo/pull-requests/42' } }
      },
      repository: { full_name: 'owner/repo', uuid: 'abc-def-123' },
      actor: { username: 'dev1' }
    }.to_json

    assert_difference 'ExternalPullRequest.count', 1 do
      perform_enqueued_jobs do
        post '/dev_integrations/bitbucket/webhook',
             headers: bitbucket_headers(event: 'pullrequest:created', payload: payload)
      end
    end

    assert_response :accepted

    pr = ExternalPullRequest.last
    assert_equal 42, pr.number
    assert_equal 'bitbucket', pr.provider
    assert_equal @repo, pr.external_repository
    assert_equal 'open', pr.state
    assert_equal 'dev1', pr.author_login
    assert pr.issues.exists?(@issue.id)
  end

  def test_pullrequest_fulfilled_triggers_pr_merged
    payload = {
      pullrequest: {
        id: 43,
        title: "Fix #{@issue.issue_key} merged feature",
        description: 'Merged implementation',
        state: 'MERGED',
        author: { username: 'dev1', display_name: 'Dev One' },
        source: { branch: { name: "feature/#{@issue.issue_key}-merged" }, commit: { hash: 'abc123def456789012345678901234567890abcd' } },
        destination: { branch: { name: 'main' }, commit: { hash: 'base999base999' } },
        merge_commit: { hash: 'merge999merge999' },
        created_on: '2026-01-01T00:00:00Z',
        updated_on: '2026-01-01T12:00:00Z',
        links: { html: { href: 'https://bitbucket.org/owner/repo/pull-requests/43' } }
      },
      repository: { full_name: 'owner/repo', uuid: 'abc-def-123' },
      actor: { username: 'dev1' }
    }.to_json

    assert_difference 'ExternalPullRequest.count', 1 do
      perform_enqueued_jobs do
        post '/dev_integrations/bitbucket/webhook',
             headers: bitbucket_headers(event: 'pullrequest:fulfilled', payload: payload)
      end
    end

    assert_response :accepted

    pr = ExternalPullRequest.last
    assert_equal 'closed', pr.state
    assert_equal true, pr.merged
    assert_not_nil pr.merge_commit_sha
    assert_not_nil pr.merged_at
  end

  def test_pullrequest_rejected_triggers_pr_closed
    payload = {
      pullrequest: {
        id: 44,
        title: "Fix #{@issue.issue_key} rejected pr",
        description: 'Rejected PR',
        state: 'DECLINED',
        author: { username: 'dev1', display_name: 'Dev One' },
        source: { branch: { name: "feature/#{@issue.issue_key}-rejected" }, commit: { hash: 'abc123def456789012345678901234567890abcd' } },
        destination: { branch: { name: 'main' }, commit: { hash: 'base999base999' } },
        created_on: '2026-01-01T00:00:00Z',
        updated_on: '2026-01-01T12:00:00Z',
        links: { html: { href: 'https://bitbucket.org/owner/repo/pull-requests/44' } }
      },
      repository: { full_name: 'owner/repo', uuid: 'abc-def-123' },
      actor: { username: 'dev1' }
    }.to_json

    assert_difference 'ExternalPullRequest.count', 1 do
      perform_enqueued_jobs do
        post '/dev_integrations/bitbucket/webhook',
             headers: bitbucket_headers(event: 'pullrequest:rejected', payload: payload)
      end
    end

    assert_response :accepted

    pr = ExternalPullRequest.last
    assert_equal 'closed', pr.state
    assert_equal false, pr.merged
  end

  def test_commit_status_created_creates_build_record
    payload = {
      commit_status: {
        key: 'BUILD-123',
        name: "CI Build #{@issue.issue_key}",
        state: 'SUCCESSFUL',
        url: 'https://bitbucket.org/owner/repo/addon/pipelines/home#!/results/123',
        commit: { hash: 'abc123def456789012345678901234567890abcd' },
        refname: "feature/#{@issue.issue_key}-login",
        description: "feat: #{@issue.issue_key} login",
        created_on: '2026-01-01T00:00:00Z',
        updated_on: '2026-01-01T00:05:00Z'
      },
      repository: { full_name: 'owner/repo', uuid: 'abc-def-123' }
    }.to_json

    assert_difference 'ExternalBuild.count', 1 do
      perform_enqueued_jobs do
        post '/dev_integrations/bitbucket/webhook',
             headers: bitbucket_headers(event: 'repo:commit_status_created', payload: payload)
      end
    end

    assert_response :accepted

    build = ExternalBuild.last
    assert_equal 'bitbucket', build.provider
    assert_equal 'BUILD-123', build.provider_build_id
    assert_equal 'SUCCESSFUL', build.conclusion
    assert_equal 'success', build.status
    assert build.issues.exists?(@issue.id)
  end

  def test_repo_deployment_creates_deployment_record
    payload = {
      deployment: {
        uuid: 'deploy-uuid-888',
        environment: { name: 'staging' },
        state: { name: 'COMPLETED', result: { name: 'SUCCESSFUL' } },
        release: { commit: 'abc123def456789012345678901234567890abcd', name: "feature/#{@issue.issue_key}-login", url: 'https://staging.example.com' },
        comment: "Deploy #{@issue.issue_key} to staging",
        deployer: { username: 'dev1', display_name: 'Dev One' },
        started_on: '2026-01-01T00:00:00Z',
        completed_on: '2026-01-01T00:05:00Z',
        updated_on: '2026-01-01T00:05:00Z'
      },
      repository: { full_name: 'owner/repo', uuid: 'abc-def-123' }
    }.to_json

    assert_difference 'ExternalDeployment.count', 1 do
      perform_enqueued_jobs do
        post '/dev_integrations/bitbucket/webhook',
             headers: bitbucket_headers(event: 'repo:deployment', payload: payload)
      end
    end

    assert_response :accepted

    deployment = ExternalDeployment.last
    assert_equal 'bitbucket', deployment.provider
    assert_equal 'deploy-uuid-888', deployment.provider_deployment_id
    assert_equal 'staging', deployment.environment_name
    assert_equal 'success', deployment.status
    assert deployment.issues.exists?(@issue.id)
  end

  private

  def bitbucket_headers(event:, payload:)
    {
      'RAW_POST_DATA' => payload,
      'CONTENT_TYPE' => 'application/json',
      'X-Hub-Signature-256' => valid_bitbucket_signature(payload),
      'X-Request-Id' => "req-#{SecureRandom.hex(8)}",
      'X-Event-Key' => event
    }
  end

  def valid_bitbucket_signature(payload)
    digest = OpenSSL::HMAC.hexdigest('SHA256', 'test_secret', payload)
    "sha256=#{digest}"
  end
end
