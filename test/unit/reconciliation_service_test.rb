# frozen_string_literal: true

require_relative '../test_helper'

class ReconciliationServiceTest < ActiveSupport::TestCase
  fixtures :projects, :repositories

  StubClient = Struct.new(:pull_requests, :builds, :deployments, :credentials_missing_flag, :failure_mode, keyword_init: true) do
    def credentials_missing?
      credentials_missing_flag == true
    end

    def recent_pull_requests(repository:)
      maybe_raise(:recent_pull_requests)

      pull_requests || []
    end

    def recent_builds(repository:)
      maybe_raise(:recent_builds)

      builds || []
    end

    def recent_deployments(repository:)
      maybe_raise(:recent_deployments)

      deployments || []
    end

    def maybe_raise(method_name)
      return unless failure_mode.present?

      if failure_mode == method_name
        raise StandardError, 'boom'
      elsif failure_mode.is_a?(Exception)
        raise failure_mode
      end
    end
  end

  def setup
    @project = projects(:projects_001)
    @repository = ExternalRepository.create!(
      provider: 'github',
      provider_repository_id: '123',
      owner: 'redmine',
      repo_name: 'redmine_dev_integration',
      full_name: 'redmine/redmine_dev_integration',
      url: 'https://github.com/redmine/redmine_dev_integration',
      redmine_project: @project,
      redmine_repository: nil,
      active: true
    )
  end

  def test_reconciles_active_repository_and_imports_records_for_github
    project = Project.generate!(issue_key_prefix: 'AUTH')
    @repository.update!(redmine_project: project)
    issue = Issue.generate!(project: project, subject: 'Fix login')
    client = StubClient.new(
      pull_requests: [
        {
          number: 7,
          title: "Add #{issue.issue_key} support",
          body: 'Pull request body',
          url: 'https://github.com/redmine/redmine_dev_integration/pull/7',
          state: 'open',
          author_login: 'contributor',
          source_branch: "feature/#{issue.issue_key}-login",
          target_branch: 'main',
          merged: false,
          opened_at: Time.zone.parse('2026-05-25T10:00:00Z'),
          last_event_at: Time.zone.parse('2026-05-25T10:05:00Z')
        }
      ],
      builds: [
        {
          provider_build_id: '101',
          build_number: 42,
          name: "CI build for #{issue.issue_key}",
          status: 'success',
          conclusion: 'success',
          url: 'https://github.com/redmine/redmine_dev_integration/actions/runs/101',
          sha: 'abc123',
          ref: "feature/#{issue.issue_key}-login",
          branch_name: "feature/#{issue.issue_key}-login",
          author_login: 'contributor',
          started_at: Time.zone.parse('2026-05-25T10:10:00Z'),
          finished_at: Time.zone.parse('2026-05-25T10:20:00Z'),
          last_event_at: Time.zone.parse('2026-05-25T10:25:00Z')
        }
      ],
      deployments: [
        {
          provider_deployment_id: '9001',
          environment_name: 'staging',
          environment_url: 'https://staging.example.test',
          status: 'success',
          sha: 'abc123',
          ref: "feature/#{issue.issue_key}-login",
          branch_name: "feature/#{issue.issue_key}-login",
          description: "Deploy #{issue.issue_key} to staging",
          creator_login: 'contributor',
          started_at: Time.zone.parse('2026-05-25T10:30:00Z'),
          completed_at: Time.zone.parse('2026-05-25T10:40:00Z'),
          last_event_at: Time.zone.parse('2026-05-25T10:45:00Z')
        }
      ]
    )

    travel_to Time.zone.local(2026, 5, 25, 13, 0, 0) do
      result = service_with(client).call(project: project, repository: @repository, provider: 'github')

      assert_predicate result, :reconciled?
      assert_equal :last_synced_at_updated, result.reason
      assert_equal Time.current, @repository.reload.last_synced_at

      pull_request = ExternalPullRequest.find_by!(provider: 'github', external_repository: @repository, number: 7)
      build = ExternalBuild.find_by!(provider: 'github', external_repository: @repository, provider_build_id: '101')
      deployment = ExternalDeployment.find_by!(
        provider: 'github',
        external_repository: @repository,
        provider_deployment_id: '9001',
        environment_name: 'staging'
      )

      assert_equal [issue.id], pull_request.issues.pluck(:id)
      assert_equal [issue.id], build.issues.pluck(:id)
      assert_equal [issue.id], deployment.issues.pluck(:id)
    end
  end

  def test_reconciles_gitlab_repository_and_updates_existing_records
    @repository.update!(provider: 'gitlab', provider_repository_id: '456')

    existing_pull_request = ExternalPullRequest.create!(
      provider: 'gitlab',
      external_repository: @repository,
      number: 7,
      title: 'Old title',
      body: 'Old body',
      url: 'https://gitlab.example.com/redmine/redmine_dev_integration/-/merge_requests/7',
      state: 'open',
      merged: false
    )
    existing_build = ExternalBuild.create!(
      provider: 'gitlab',
      external_repository: @repository,
      provider_build_id: '101',
      build_number: 12,
      name: 'Old pipeline',
      status: 'queued',
      conclusion: 'created'
    )
    existing_deployment = ExternalDeployment.create!(
      provider: 'gitlab',
      external_repository: @repository,
      provider_deployment_id: '9001',
      environment_name: 'staging',
      status: 'pending'
    )

    client = StubClient.new(
      pull_requests: [
        {
          number: 7,
          title: 'Updated AUTH-1 title',
          body: 'Updated body',
          url: 'https://gitlab.example.com/redmine/redmine_dev_integration/-/merge_requests/7',
          state: 'closed',
          author_login: 'contributor',
          source_branch: 'feature/AUTH-1',
          target_branch: 'main',
          merged: true,
          merged_at: Time.zone.parse('2026-05-25T12:00:00Z'),
          closed_at: Time.zone.parse('2026-05-25T12:00:00Z'),
          last_event_at: Time.zone.parse('2026-05-25T12:05:00Z')
        }
      ],
      builds: [
        {
          provider_build_id: '101',
          build_number: 42,
          name: 'Updated pipeline',
          status: 'failed',
          conclusion: 'failed',
          url: 'https://gitlab.example.com/redmine/redmine_dev_integration/-/pipelines/101',
          sha: 'def456',
          ref: 'main',
          branch_name: 'main',
          author_login: 'contributor',
          started_at: Time.zone.parse('2026-05-25T12:10:00Z'),
          finished_at: Time.zone.parse('2026-05-25T12:20:00Z'),
          last_event_at: Time.zone.parse('2026-05-25T12:25:00Z')
        }
      ],
      deployments: [
        {
          provider_deployment_id: '9001',
          environment_name: 'staging',
          environment_url: 'https://staging.example.test',
          status: 'failed',
          sha: 'def456',
          ref: 'main',
          branch_name: 'main',
          description: 'Updated deploy',
          creator_login: 'contributor',
          started_at: Time.zone.parse('2026-05-25T12:30:00Z'),
          completed_at: Time.zone.parse('2026-05-25T12:40:00Z'),
          last_event_at: Time.zone.parse('2026-05-25T12:45:00Z')
        }
      ]
    )

    travel_to Time.zone.local(2026, 5, 25, 14, 0, 0) do
      result = service_with(client).call(project: @project, repository: @repository, provider: 'gitlab')

      assert_predicate result, :reconciled?
      assert_equal 1, ExternalPullRequest.where(provider: 'gitlab', external_repository: @repository, number: 7).count
      assert_equal 1, ExternalBuild.where(provider: 'gitlab', external_repository: @repository, provider_build_id: '101').count
      assert_equal 1, ExternalDeployment.where(provider: 'gitlab', external_repository: @repository, provider_deployment_id: '9001', environment_name: 'staging').count

      assert_equal 'Updated AUTH-1 title', existing_pull_request.reload.title
      assert_equal 'failed', existing_build.reload.status
      assert_equal 'failed', existing_deployment.reload.status
      assert_equal Time.current, @repository.reload.last_synced_at
    end
  end

  def test_skips_unsupported_provider_without_touching_repository
    result = RedmineDevIntegration::ReconciliationService.new.call(project: @project, repository: @repository, provider: 'unsupported')

    assert_predicate result, :skipped?
    assert_equal :unsupported_provider, result.reason
    assert_nil @repository.reload.last_synced_at
  end

  def test_skips_bitbucket_when_credentials_missing
    @repository.update!(provider: 'bitbucket')

    result = RedmineDevIntegration::ReconciliationService.new.call(project: @project, repository: @repository, provider: 'bitbucket')

    assert_predicate result, :skipped?
    assert_equal :credentials_missing, result.reason
    assert_nil @repository.reload.last_synced_at
  end

  def test_reconciles_bitbucket_repository_and_imports_records
    @repository.update!(provider: 'bitbucket', provider_repository_id: 'abc123-def4-5678-9012-3456789abcde')

    project = Project.generate!(issue_key_prefix: 'AUTH')
    @repository.update!(redmine_project: project)
    issue = Issue.generate!(project: project, subject: 'Fix login')

    client = StubClient.new(
      pull_requests: [
        {
          number: 7,
          title: "Add #{issue.issue_key} support",
          body: 'Pull request body',
          url: 'https://bitbucket.org/workspace/repo/pull-requests/7',
          state: 'open',
          author_login: 'contributor',
          source_branch: "feature/#{issue.issue_key}-login",
          target_branch: 'main',
          merged: false,
          opened_at: Time.zone.parse('2026-05-25T10:00:00Z'),
          last_event_at: Time.zone.parse('2026-05-25T10:05:00Z')
        }
      ],
      builds: [
        {
          provider_build_id: 'pipeline-uuid-101',
          build_number: 42,
          name: "Pipeline ##{issue.issue_key}",
          status: 'success',
          conclusion: 'SUCCESSFUL',
          url: 'https://bitbucket.org/workspace/repo/pipelines/results/42',
          sha: 'abc123',
          ref: "feature/#{issue.issue_key}-login",
          branch_name: "feature/#{issue.issue_key}-login",
          author_login: 'contributor',
          started_at: Time.zone.parse('2026-05-25T10:10:00Z'),
          finished_at: Time.zone.parse('2026-05-25T10:20:00Z'),
          last_event_at: Time.zone.parse('2026-05-25T10:25:00Z')
        }
      ],
      deployments: [
        {
          provider_deployment_id: 'deploy-uuid-9001',
          environment_name: 'staging',
          environment_url: 'https://staging.example.test',
          status: 'success',
          sha: 'abc123',
          ref: "feature/#{issue.issue_key}-login",
          branch_name: "feature/#{issue.issue_key}-login",
          description: "Deploy #{issue.issue_key} to staging",
          creator_login: 'contributor',
          started_at: Time.zone.parse('2026-05-25T10:30:00Z'),
          completed_at: Time.zone.parse('2026-05-25T10:40:00Z'),
          last_event_at: Time.zone.parse('2026-05-25T10:45:00Z')
        }
      ]
    )

    travel_to Time.zone.local(2026, 5, 25, 13, 0, 0) do
      result = service_with(client).call(project: project, repository: @repository, provider: 'bitbucket')

      assert_predicate result, :reconciled?
      assert_equal :last_synced_at_updated, result.reason
      assert_equal Time.current, @repository.reload.last_synced_at

      pull_request = ExternalPullRequest.find_by!(provider: 'bitbucket', external_repository: @repository, number: 7)
      build = ExternalBuild.find_by!(provider: 'bitbucket', external_repository: @repository, provider_build_id: 'pipeline-uuid-101')
      deployment = ExternalDeployment.find_by!(
        provider: 'bitbucket',
        external_repository: @repository,
        provider_deployment_id: 'deploy-uuid-9001',
        environment_name: 'staging'
      )

      assert_equal [issue.id], pull_request.issues.pluck(:id)
      assert_equal [issue.id], build.issues.pluck(:id)
      assert_equal [issue.id], deployment.issues.pluck(:id)
    end
  end

  def test_skips_inactive_repository
    @repository.update!(active: false)

    result = RedmineDevIntegration::ReconciliationService.new.call(project: @project, repository: @repository, provider: 'github')

    assert_predicate result, :skipped?
    assert_equal :inactive_repository, result.reason
    assert_nil @repository.reload.last_synced_at
  end

  def test_skips_project_mismatch
    other_project = Project.generate!(issue_key_prefix: 'OPS')

    result = RedmineDevIntegration::ReconciliationService.new.call(project: other_project, repository: @repository, provider: 'github')

    assert_predicate result, :skipped?
    assert_equal :project_mismatch, result.reason
    assert_nil @repository.reload.last_synced_at
  end

  def test_skips_when_credentials_are_missing
    client = StubClient.new(credentials_missing_flag: true)

    result = service_with(client).call(project: @project, repository: @repository, provider: 'github')

    assert_predicate result, :skipped?
    assert_equal :credentials_missing, result.reason
    assert_nil @repository.reload.last_synced_at
  end

  def test_returns_failed_when_provider_client_raises_and_keeps_existing_records_unchanged
    existing_pull_request = ExternalPullRequest.create!(
      provider: 'github',
      external_repository: @repository,
      number: 7,
      title: 'Old title',
      body: 'Old body',
      url: 'https://github.com/redmine/redmine_dev_integration/pull/7',
      state: 'open',
      merged: false
    )
    original_title = existing_pull_request.title

    client = StubClient.new(failure_mode: RuntimeError.new('boom'))

    result = service_with(client).call(project: @project, repository: @repository, provider: 'github')

    assert_predicate result, :failed?
    assert_equal :api_failure, result.reason
    assert_nil @repository.reload.last_synced_at
    assert_equal original_title, existing_pull_request.reload.title
  end

  private

  def service_with(client)
    RedmineDevIntegration::ReconciliationService.new(provider_client_factory: ->(_provider) { client })
  end
end
