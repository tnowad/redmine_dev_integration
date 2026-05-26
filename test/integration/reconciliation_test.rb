# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/dev_integration_test_factory'

class ReconciliationTest < ActiveSupport::TestCase
  include DevIntegrationTestFactory

  def setup
    @project = create_project_with_prefix(name: 'recon_int', prefix: 'DEV')
    @issue = create_issue_with_key(project: @project, subject: 'Fix login')
    @repo = create_external_repository(project: @project, provider: 'github', full_name: 'owner/repo', provider_repository_id: '12345')
  end

  def test_full_sync_upserts_prs_builds_and_deployments
    mock_client = build_mock_client(
      pull_requests: [
        { 'number' => 1, 'title' => "Test PR #{@issue.issue_key}", 'body' => 'Body', 'url' => 'https://github.com/owner/repo/pull/1', 'state' => 'open', 'author_login' => 'dev1', 'source_branch' => "feature/#{@issue.issue_key}-a", 'target_branch' => 'main', 'merged' => false, 'merged_at' => nil, 'opened_at' => '2026-01-01T00:00:00Z', 'updated_at' => '2026-01-01T00:00:00Z' },
        { 'number' => 2, 'title' => "Test PR 2 #{@issue.issue_key}", 'body' => 'Body 2', 'url' => 'https://github.com/owner/repo/pull/2', 'state' => 'open', 'author_login' => 'dev2', 'source_branch' => "feature/#{@issue.issue_key}-b", 'target_branch' => 'main', 'merged' => false, 'merged_at' => nil, 'opened_at' => '2026-01-01T01:00:00Z', 'updated_at' => '2026-01-01T01:00:00Z' }
      ],
      builds: [
        { 'provider_build_id' => 'run-1', 'build_number' => 1, 'name' => "CI #{@issue.issue_key}", 'status' => 'success', 'url' => 'https://github.com/owner/repo/actions/runs/1', 'sha' => 'abc', 'ref' => 'main', 'branch_name' => 'main', 'author_login' => 'dev1', 'started_at' => '2026-01-01T00:00:00Z' }
      ],
      deployments: [
        { 'provider_deployment_id' => 'deploy-1', 'environment_name' => 'staging', 'status' => 'success', 'sha' => 'abc', 'ref' => 'main', 'branch_name' => 'main', 'creator_login' => 'dev1', 'created_at' => '2026-01-01T00:00:00Z' }
      ]
    )

    result = RedmineDevIntegration::ReconciliationService.new(
      provider_client_factory: ->(_provider) { mock_client }
    ).call(project: @project, repository: @repo)

    assert_predicate result, :reconciled?
    assert_equal :last_synced_at_updated, result.reason
    assert_equal 2, ExternalPullRequest.where(provider: 'github', external_repository: @repo).count
    assert_equal 1, ExternalBuild.where(provider: 'github', external_repository: @repo).count
    assert_equal 1, ExternalDeployment.where(provider: 'github', external_repository: @repo).count
  end

  def test_last_synced_at_updated_after_sync
    mock_client = build_mock_client

    assert_nil @repo.last_synced_at

    result = RedmineDevIntegration::ReconciliationService.new(
      provider_client_factory: ->(_provider) { mock_client }
    ).call(project: @project, repository: @repo)

    assert_predicate result, :reconciled?
    assert_not_nil @repo.reload.last_synced_at
  end

  def test_no_duplicates_on_resync
    mock_client = build_mock_client(
      pull_requests: [
        { 'number' => 1, 'title' => "Test PR #{@issue.issue_key}", 'body' => 'Body', 'url' => 'https://github.com/owner/repo/pull/1', 'state' => 'open', 'author_login' => 'dev1', 'source_branch' => "feature/#{@issue.issue_key}-a", 'target_branch' => 'main', 'merged' => false, 'merged_at' => nil, 'opened_at' => '2026-01-01T00:00:00Z', 'updated_at' => '2026-01-01T00:00:00Z' }
      ]
    )

    service = RedmineDevIntegration::ReconciliationService.new(
      provider_client_factory: ->(_provider) { mock_client }
    )

    first_result = service.call(project: @project, repository: @repo)
    assert_predicate first_result, :reconciled?
    assert_equal 1, ExternalPullRequest.where(provider: 'github', external_repository: @repo, number: 1).count

    second_result = service.call(project: @project, repository: @repo)
    assert_predicate second_result, :reconciled?
    assert_equal 1, ExternalPullRequest.where(provider: 'github', external_repository: @repo, number: 1).count
  end

  def test_skips_with_credentials_missing
    mock_client = mock('GitHubClient')
    mock_client.stubs(:credentials_missing?).returns(true)

    result = RedmineDevIntegration::ReconciliationService.new(
      provider_client_factory: ->(_provider) { mock_client }
    ).call(project: @project, repository: @repo)

    assert_predicate result, :skipped?
    assert_equal :credentials_missing, result.reason
    assert_nil @repo.reload.last_synced_at
  end

  def test_skips_with_inactive_repository
    @repo.update!(active: false)

    result = RedmineDevIntegration::ReconciliationService.new.call(project: @project, repository: @repo)

    assert_predicate result, :skipped?
    assert_equal :inactive_repository, result.reason
    assert_nil @repo.reload.last_synced_at
  end

  def test_skips_with_unsupported_provider
    result = RedmineDevIntegration::ReconciliationService.new.call(project: @project, repository: @repo, provider: 'unknown')

    assert_predicate result, :skipped?
    assert_equal :unsupported_provider, result.reason
    assert_nil @repo.reload.last_synced_at
  end

  def test_skips_with_project_mismatch
    other_project = Project.generate!(issue_key_prefix: 'OPS')

    result = RedmineDevIntegration::ReconciliationService.new.call(project: other_project, repository: @repo)

    assert_predicate result, :skipped?
    assert_equal :project_mismatch, result.reason
    assert_nil @repo.reload.last_synced_at
  end

  private

  def build_mock_client(pull_requests: [], builds: [], deployments: [])
    mock_client = mock('GitHubClient')
    mock_client.stubs(:credentials_missing?).returns(false)
    mock_client.stubs(:recent_pull_requests).with(repository: @repo).returns(pull_requests)
    mock_client.stubs(:recent_builds).with(repository: @repo).returns(builds)
    mock_client.stubs(:recent_deployments).with(repository: @repo).returns(deployments)
    mock_client
  end
end
