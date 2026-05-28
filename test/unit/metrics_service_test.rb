# frozen_string_literal: true

require_relative '../test_helper'

class MetricsServiceTest < ActiveSupport::TestCase
  fixtures :projects, :repositories

  def setup
    @project = Project.find(1)
    @project.enable_module!(:redmine_dev_integration)

    @repo = ExternalRepository.create!(
      provider: 'github',
      provider_repository_id: 'metrics-test-789',
      owner: 'redmine',
      repo_name: 'redmine',
      full_name: 'redmine/redmine',
      url: 'https://github.com/redmine/redmine',
      redmine_project: @project,
      active: true
    )

    @service = RedmineDevIntegration::MetricsService.new
  end

  def test_empty_result_when_no_active_repositories
    @repo.update!(active: false)

    result = @service.call(project: @project, range: 30.days)
    assert_equal 0, result.deployment_frequency
    assert_equal 0, result.lead_time_hours
    assert_equal 0, result.change_failure_rate
    assert_equal 0, result.mttr_hours
    assert_equal 0, result.deployments_count
    assert_nil result.dora_band
  end

  def test_deployment_frequency_computes_deploys_per_day
    now = Time.current
    6.times do |i|
      ExternalDeployment.create!(
        provider: 'github',
        external_repository: @repo,
        provider_deployment_id: "df-test-#{i}",
        environment_name: 'production',
        status: 'success',
        completed_at: now - i.days
      )
    end

    result = @service.call(project: @project, range: 30.days)
    assert_equal 0.2, result.deployment_frequency
    assert_equal 6, result.deployments_count
    assert_equal 6, result.success_count
  end

  def test_lead_time_averages_pr_open_to_merge
    now = Time.current
    ExternalPullRequest.create!(
      provider: 'github',
      external_repository: @repo,
      number: 1,
      title: 'Fix bug',
      url: 'https://github.com/redmine/redmine/pull/1',
      state: 'closed',
      merged: true,
      opened_at: now - 5.hours,
      merged_at: now - 2.hours
    )
    ExternalPullRequest.create!(
      provider: 'github',
      external_repository: @repo,
      number: 2,
      title: 'Add feature',
      url: 'https://github.com/redmine/redmine/pull/2',
      state: 'closed',
      merged: true,
      opened_at: now - 10.hours,
      merged_at: now - 4.hours
    )

    result = @service.call(project: @project, range: 30.days)
    assert_equal 4.5, result.lead_time_hours
  end

  def test_lead_time_returns_zero_when_no_prs
    result = @service.call(project: @project, range: 30.days)
    assert_equal 0, result.lead_time_hours
  end

  def test_lead_time_ignores_unmerged_prs
    now = Time.current
    ExternalPullRequest.create!(
      provider: 'github',
      external_repository: @repo,
      number: 1,
      title: 'WIP',
      url: 'https://github.com/redmine/redmine/pull/1',
      state: 'open',
      merged: false,
      opened_at: now - 5.hours
    )

    result = @service.call(project: @project, range: 30.days)
    assert_equal 0, result.lead_time_hours
  end

  def test_lead_time_from_commit_timestamps
    now = Time.current
    sha1 = 'a' * 40
    sha2 = 'b' * 40

    ExternalCommit.create!(
      provider: 'github',
      external_repository: @repo,
      provider_commit_id: sha1,
      sha: sha1,
      message: 'Fix bug',
      committed_at: now - 10.hours
    )
    ExternalCommit.create!(
      provider: 'github',
      external_repository: @repo,
      provider_commit_id: sha2,
      sha: sha2,
      message: 'Add feature',
      committed_at: now - 5.hours
    )

    ExternalDeployment.create!(
      provider: 'github',
      external_repository: @repo,
      provider_deployment_id: 'deploy-1',
      environment_name: 'production',
      status: 'success',
      sha: sha1,
      completed_at: now - 2.hours
    )
    ExternalDeployment.create!(
      provider: 'github',
      external_repository: @repo,
      provider_deployment_id: 'deploy-2',
      environment_name: 'production',
      status: 'success',
      sha: sha2,
      completed_at: now - 1.hour
    )

    result = @service.call(project: @project, range: 30.days)
    assert_equal 6.0, result.lead_time_hours
  end

  def test_lead_time_falls_back_to_pr_when_no_matching_commits
    now = Time.current
    ExternalDeployment.create!(
      provider: 'github',
      external_repository: @repo,
      provider_deployment_id: 'deploy-no-commit',
      environment_name: 'production',
      status: 'success',
      sha: 'c' * 40,
      completed_at: now - 1.hour
    )

    ExternalPullRequest.create!(
      provider: 'github',
      external_repository: @repo,
      number: 1,
      title: 'Fix bug',
      url: 'https://github.com/redmine/redmine/pull/1',
      state: 'closed',
      merged: true,
      opened_at: now - 5.hours,
      merged_at: now - 2.hours
    )

    result = @service.call(project: @project, range: 30.days)
    assert_equal 3.0, result.lead_time_hours
  end

  def test_lead_time_ignores_deployments_without_sha
    now = Time.current
    ExternalDeployment.create!(
      provider: 'github',
      external_repository: @repo,
      provider_deployment_id: 'deploy-no-sha',
      environment_name: 'production',
      status: 'success',
      sha: nil,
      completed_at: now - 1.hour
    )

    result = @service.call(project: @project, range: 30.days)
    assert_equal 0, result.lead_time_hours
  end

  def test_change_failure_rate_percentage
    now = Time.current
    ExternalDeployment.create!(
      provider: 'github',
      external_repository: @repo,
      provider_deployment_id: 'cfr-success-1',
      environment_name: 'production',
      status: 'success',
      completed_at: now - 1.day
    )
    ExternalDeployment.create!(
      provider: 'github',
      external_repository: @repo,
      provider_deployment_id: 'cfr-success-2',
      environment_name: 'production',
      status: 'success',
      completed_at: now - 2.days
    )
    ExternalDeployment.create!(
      provider: 'github',
      external_repository: @repo,
      provider_deployment_id: 'cfr-success-3',
      environment_name: 'production',
      status: 'success',
      completed_at: now - 3.days
    )
    ExternalDeployment.create!(
      provider: 'github',
      external_repository: @repo,
      provider_deployment_id: 'cfr-fail-1',
      environment_name: 'production',
      status: 'failed',
      completed_at: now - 4.days
    )

    result = @service.call(project: @project, range: 30.days)
    assert_equal 25.0, result.change_failure_rate
    assert_equal 1, result.failures_count
    assert_equal 3, result.success_count
    assert_equal 4, result.deployments_count
  end

  def test_change_failure_rate_zero_when_no_deployments
    result = @service.call(project: @project, range: 30.days)
    assert_equal 0, result.change_failure_rate
  end

  def test_change_failure_rate_all_success
    now = Time.current
    ExternalDeployment.create!(
      provider: 'github',
      external_repository: @repo,
      provider_deployment_id: 'all-success-1',
      environment_name: 'production',
      status: 'success',
      completed_at: now - 1.day
    )

    result = @service.call(project: @project, range: 30.days)
    assert_equal 0, result.change_failure_rate
  end

  def test_mttr_computes_average_recovery_time
    now = Time.current
    ExternalIncident.create!(
      external_repository: @repo,
      title: 'Incident 1',
      status: 'resolved',
      severity: 'high',
      started_at: now - 4.hours,
      resolved_at: now - 2.hours
    )
    ExternalDeployment.create!(
      provider: 'github',
      external_repository: @repo,
      provider_deployment_id: 'mttr-success-1',
      environment_name: 'production',
      status: 'success',
      completed_at: now - 1.hour
    )

    result = @service.call(project: @project, range: 30.days)
    assert_equal 2.0, result.mttr_hours
  end

  def test_mttr_returns_zero_when_no_failures
    now = Time.current
    ExternalDeployment.create!(
      provider: 'github',
      external_repository: @repo,
      provider_deployment_id: 'no-fail-1',
      environment_name: 'production',
      status: 'success',
      completed_at: now - 1.hour
    )

    result = @service.call(project: @project, range: 30.days)
    assert_equal 0, result.mttr_hours
  end

  def test_mttr_ignores_failures_without_subsequent_success
    now = Time.current
    ExternalDeployment.create!(
      provider: 'github',
      external_repository: @repo,
      provider_deployment_id: 'fail-no-recovery',
      environment_name: 'production',
      status: 'failed',
      completed_at: now - 1.hour
    )

    result = @service.call(project: @project, range: 30.days)
    assert_equal 0, result.mttr_hours
  end

  def test_trend_data_groups_by_day
    now = Time.current
    ExternalDeployment.create!(
      provider: 'github',
      external_repository: @repo,
      provider_deployment_id: 'trend-1',
      environment_name: 'production',
      status: 'success',
      completed_at: now - 1.day
    )
    ExternalDeployment.create!(
      provider: 'github',
      external_repository: @repo,
      provider_deployment_id: 'trend-2',
      environment_name: 'production',
      status: 'success',
      completed_at: now - 1.day
    )

    result = @service.call(project: @project, range: 7.days)
    assert result.trend_data.is_a?(Array)
    assert result.trend_data.any? { |d| d[:count] > 0 }
  end

  def test_env_breakdown_groups_by_environment
    now = Time.current
    ExternalDeployment.create!(
      provider: 'github',
      external_repository: @repo,
      provider_deployment_id: 'env-prod-1',
      environment_name: 'production',
      status: 'success',
      completed_at: now - 1.day
    )
    ExternalDeployment.create!(
      provider: 'github',
      external_repository: @repo,
      provider_deployment_id: 'env-stag-1',
      environment_name: 'staging',
      status: 'failed',
      completed_at: now - 2.days
    )

    result = @service.call(project: @project, range: 30.days)
    assert_equal 2, result.env_breakdown.size
    production = result.env_breakdown.find { |e| e[:environment] == 'production' }
    staging = result.env_breakdown.find { |e| e[:environment] == 'staging' }
    assert_equal 1, production[:successes]
    assert_equal 0, production[:failures]
    assert_equal 0, staging[:successes]
    assert_equal 1, staging[:failures]
    assert_equal 100.0, staging[:failure_rate]
  end

  def test_dora_band_elite
    now = Time.current
    30.times do |i|
      ExternalDeployment.create!(
        provider: 'github',
        external_repository: @repo,
        provider_deployment_id: "elite-#{i}",
        environment_name: 'production',
        status: 'success',
        completed_at: now - i.days
      )
    end
    ExternalPullRequest.create!(
      provider: 'github',
      external_repository: @repo,
      number: 1,
      title: 'Elite PR',
      url: 'https://github.com/redmine/redmine/pull/1',
      state: 'closed',
      merged: true,
      opened_at: now - 30.minutes,
      merged_at: now - 15.minutes
    )

    result = @service.call(project: @project, range: 30.days)
    assert_equal 'elite', result.dora_band
  end

  def test_dora_band_low_for_no_data
    result = @service.call(project: @project, range: 30.days)
    assert_nil result.dora_band
  end

  def test_deployments_outside_range_excluded
    now = Time.current
    ExternalDeployment.create!(
      provider: 'github',
      external_repository: @repo,
      provider_deployment_id: 'old-deploy-1',
      environment_name: 'production',
      status: 'success',
      completed_at: now - 40.days
    )

    result = @service.call(project: @project, range: 30.days)
    assert_equal 0, result.deployments_count
  end

  def test_ignores_non_success_failed_statuses
    now = Time.current
    ExternalDeployment.create!(
      provider: 'github',
      external_repository: @repo,
      provider_deployment_id: 'pending-1',
      environment_name: 'production',
      status: 'pending',
      completed_at: now - 1.day
    )
    ExternalDeployment.create!(
      provider: 'github',
      external_repository: @repo,
      provider_deployment_id: 'in-progress-1',
      environment_name: 'production',
      status: 'in_progress',
      completed_at: now - 1.day
    )

    result = @service.call(project: @project, range: 30.days)
    assert_equal 0, result.deployments_count
  end

  def test_rollback_counted_as_failure
    now = Time.current
    ExternalDeployment.create!(
      provider: 'github',
      external_repository: @repo,
      provider_deployment_id: 'rollback-1',
      environment_name: 'production',
      status: 'success',
      rollback: true,
      completed_at: now - 1.day
    )
    ExternalDeployment.create!(
      provider: 'github',
      external_repository: @repo,
      provider_deployment_id: 'success-1',
      environment_name: 'production',
      status: 'success',
      rollback: false,
      completed_at: now - 2.days
    )
    ExternalDeployment.create!(
      provider: 'github',
      external_repository: @repo,
      provider_deployment_id: 'fail-1',
      environment_name: 'production',
      status: 'failed',
      rollback: false,
      completed_at: now - 3.days
    )

    result = @service.call(project: @project, range: 30.days)

    assert_equal 1, result.success_count
    assert_equal 2, result.failures_count
    assert_equal 3, result.deployments_count
    assert_equal 66.7, result.change_failure_rate
  end
end
