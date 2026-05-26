# frozen_string_literal: true

require_relative '../test_helper'

class ScheduledReconciliationRunnerTest < ActiveSupport::TestCase
  fixtures :projects

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
    ExternalRepository.delete_all
    Setting.plugin_redmine_dev_integration = {}
  end

  def teardown
    ExternalRepository.delete_all
    Setting.plugin_redmine_dev_integration = {}
  end

  def test_reconciles_active_repositories
    repo1 = ExternalRepository.create!(
      provider: 'github',
      provider_repository_id: '123',
      owner: 'redmine',
      repo_name: 'repo1',
      full_name: 'redmine/repo1',
      url: 'https://github.com/redmine/repo1',
      redmine_project: @project,
      active: true
    )
    repo2 = ExternalRepository.create!(
      provider: 'github',
      provider_repository_id: '456',
      owner: 'redmine',
      repo_name: 'repo2',
      full_name: 'redmine/repo2',
      url: 'https://github.com/redmine/repo2',
      redmine_project: @project,
      active: true
    )

    client = StubClient.new
    summary = runner_with(client).call

    assert_equal 2, summary[:reconciled]
    assert_equal 0, summary[:skipped]
    assert_equal 0, summary[:failed]
    assert_predicate repo1.reload.last_synced_at, :present?
    assert_predicate repo2.reload.last_synced_at, :present?
  end

  def test_skips_inactive_repositories
    repo1 = ExternalRepository.create!(
      provider: 'github',
      provider_repository_id: '001',
      owner: 'redmine',
      repo_name: 'active-repo',
      full_name: 'redmine/active-repo',
      url: 'https://github.com/redmine/active-repo',
      redmine_project: @project,
      active: true
    )
    repo2 = ExternalRepository.create!(
      provider: 'github',
      provider_repository_id: '002',
      owner: 'redmine',
      repo_name: 'inactive-repo',
      full_name: 'redmine/inactive-repo',
      url: 'https://github.com/redmine/inactive-repo',
      redmine_project: @project,
      active: false
    )

    client = StubClient.new
    summary = runner_with(client).call

    assert_equal 1, summary[:reconciled]
    assert_equal 0, summary[:skipped]
    assert_equal 0, summary[:failed]
    assert_predicate repo1.reload.last_synced_at, :present?
    assert_nil repo2.reload.last_synced_at
  end

  def test_failure_on_one_repo_does_not_stop_run
    repo1 = ExternalRepository.create!(
      provider: 'github',
      provider_repository_id: '001',
      owner: 'redmine',
      repo_name: 'good-repo',
      full_name: 'redmine/good-repo',
      url: 'https://github.com/redmine/good-repo',
      redmine_project: @project,
      active: true
    )
    repo2 = ExternalRepository.create!(
      provider: 'github',
      provider_repository_id: '002',
      owner: 'redmine',
      repo_name: 'bad-repo',
      full_name: 'redmine/bad-repo',
      url: 'https://github.com/redmine/bad-repo',
      redmine_project: @project,
      active: true
    )

    good_client = StubClient.new
    bad_client = StubClient.new(failure_mode: RuntimeError.new('boom'))
    clients = [good_client, bad_client]

    factory = -> {
      RedmineDevIntegration::ReconciliationService.new(provider_client_factory: ->(_) { clients.shift })
    }
    runner = RedmineDevIntegration::ScheduledReconciliationRunner.new(reconciliation_service_factory: factory)
    summary = runner.call

    assert_equal 1, summary[:reconciled]
    assert_equal 0, summary[:skipped]
    assert_equal 1, summary[:failed]
    assert_equal 2, summary[:results].length
  end

  def test_reconciles_only_specified_projects
    other_project = Project.generate!(issue_key_prefix: 'OPS')
    repo_this = ExternalRepository.create!(
      provider: 'github',
      provider_repository_id: '001',
      owner: 'redmine',
      repo_name: 'this-repo',
      full_name: 'redmine/this-repo',
      url: 'https://github.com/redmine/this-repo',
      redmine_project: @project,
      active: true
    )
    repo_other = ExternalRepository.create!(
      provider: 'github',
      provider_repository_id: '002',
      owner: 'redmine',
      repo_name: 'other-repo',
      full_name: 'redmine/other-repo',
      url: 'https://github.com/redmine/other-repo',
      redmine_project: other_project,
      active: true
    )

    client = StubClient.new
    summary = runner_with(client).call(projects: [@project])

    assert_equal 1, summary[:reconciled]
    assert_equal 0, summary[:skipped]
    assert_equal 0, summary[:failed]
    assert_predicate repo_this.reload.last_synced_at, :present?
    assert_nil repo_other.reload.last_synced_at
  end

  def test_skips_repos_when_provider_disabled
    Setting.plugin_redmine_dev_integration = {
      'github_provider_enabled' => '0'
    }

    repo = ExternalRepository.create!(
      provider: 'github',
      provider_repository_id: '001',
      owner: 'redmine',
      repo_name: 'disabled-repo',
      full_name: 'redmine/disabled-repo',
      url: 'https://github.com/redmine/disabled-repo',
      redmine_project: @project,
      active: true
    )

    client = StubClient.new
    summary = runner_with(client).call

    assert_equal 0, summary[:reconciled]
    assert_equal 1, summary[:skipped]
    assert_equal 0, summary[:failed]
    assert_nil repo.reload.last_synced_at
  end

  def test_returns_empty_summary_when_no_repos
    summary = RedmineDevIntegration::ScheduledReconciliationRunner.new.call

    assert_equal 0, summary[:reconciled]
    assert_equal 0, summary[:skipped]
    assert_equal 0, summary[:failed]
  end

  private

  def runner_with(client)
    factory = -> {
      RedmineDevIntegration::ReconciliationService.new(provider_client_factory: ->(_) { client })
    }
    RedmineDevIntegration::ScheduledReconciliationRunner.new(reconciliation_service_factory: factory)
  end
end
