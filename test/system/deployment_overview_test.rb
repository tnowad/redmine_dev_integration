# frozen_string_literal: true

require_relative '../../../../test/application_system_test_case'
require_relative '../support/dev_integration_test_factory'

class DeploymentOverviewTest < ApplicationSystemTestCase
  include DevIntegrationTestFactory

  def setup
    @project = Project.generate!(identifier: 'deploy-overview-test', name: 'Deploy Overview Test', issue_key_prefix: 'DEP')
    @project.enable_module!(:redmine_dev_integration)

    Role.find(1).add_permission!(:view_development_integration)

    @repo = create_external_repository(project: @project, provider: 'github', full_name: 'owner/deploy-repo', provider_repository_id: '78901')
    @issue1 = create_issue_with_key(project: @project, subject: 'Deploy fix 1')
    @issue2 = create_issue_with_key(project: @project, subject: 'Deploy fix 2')
  end

  test "deployment overview page shows heading and table" do
    create_deployment(
      env: 'staging',
      status: 'success',
      sha: 'abc123def456789',
      ref: 'main',
      issues: [@issue1],
      completed_at: 2.hours.ago,
      env_url: 'https://staging.example.com'
    )

    log_user('admin', 'admin')
    visit project_deployment_overview_path(@project)

    assert_text 'Deployment Overview'
    assert_selector 'table.list'
    within 'table.list' do
      assert_text 'staging'
      assert_text 'success'
      assert_text 'abc123de'
      assert_text 'owner/deploy-repo'
      assert_selector "a[href='#{issue_path(@issue1)}']"
    end
  end

  test "deployment overview shows one row per environment with latest deployment" do
    create_deployment(
      env: 'staging',
      status: 'success',
      sha: 'old1111111111111',
      ref: 'v1.0',
      issues: [@issue1],
      completed_at: 5.hours.ago
    )
    create_deployment(
      env: 'staging',
      status: 'failed',
      sha: 'new2222222222222',
      ref: 'v2.0',
      issues: [@issue2],
      completed_at: 1.hour.ago
    )

    log_user('admin', 'admin')
    visit project_deployment_overview_path(@project)

    within 'table.list tbody' do
      assert_selector 'tr', count: 1
      assert_text 'staging'
      assert_text 'failed'
      assert_text 'new22222'
    end
  end

  test "deployment overview shows multiple environments" do
    create_deployment(
      env: 'staging',
      status: 'success',
      sha: 'aaa1111111111111',
      ref: 'main',
      issues: [@issue1],
      completed_at: 3.hours.ago,
      env_url: 'https://staging.example.com'
    )
    create_deployment(
      env: 'production',
      status: 'success',
      sha: 'bbb2222222222222',
      ref: 'release/1.0',
      issues: [@issue2],
      completed_at: 1.hour.ago,
      env_url: 'https://prod.example.com'
    )
    create_deployment(
      env: 'dev',
      status: 'in_progress',
      sha: 'ccc3333333333333',
      ref: 'feature/test',
      issues: [],
      completed_at: nil
    )

    log_user('admin', 'admin')
    visit project_deployment_overview_path(@project)

    within 'table.list tbody' do
      assert_selector 'tr', count: 3
      assert_text 'staging'
      assert_text 'production'
      assert_text 'dev'
    end
  end

  test "deployment row shows linked issues" do
    create_deployment(
      env: 'staging',
      status: 'success',
      sha: 'abc123def456789',
      ref: 'main',
      issues: [@issue1, @issue2],
      completed_at: 1.hour.ago
    )

    log_user('admin', 'admin')
    visit project_deployment_overview_path(@project)

    assert_selector "a[href='#{issue_path(@issue1)}']"
    assert_selector "a[href='#{issue_path(@issue2)}']"
  end

  test "deployment row shows repository link with target blank" do
    create_deployment(
      env: 'staging',
      status: 'success',
      sha: 'abc123def456789',
      ref: 'main',
      issues: [],
      completed_at: 1.hour.ago
    )

    log_user('admin', 'admin')
    visit project_deployment_overview_path(@project)

    assert_selector "a[href='#{@repo.url}'][target='_blank']"
  end

  test "deployment row shows provider environment url" do
    create_deployment(
      env: 'staging',
      status: 'success',
      sha: 'abc123def456789',
      ref: 'main',
      issues: [],
      completed_at: 1.hour.ago,
      env_url: 'https://staging.example.com'
    )

    log_user('admin', 'admin')
    visit project_deployment_overview_path(@project)

    assert_selector "a[href='https://staging.example.com'][target='_blank']"
  end

  test "no deployments shows no data message" do
    log_user('admin', 'admin')
    visit project_deployment_overview_path(@project)

    assert_text 'Deployment Overview'
    assert_selector '.nodata', text: 'No data to display'
  end

  test "user without permission gets 403" do
    role = Role.generate!(name: 'No Dev Access', permissions: [:view_issues])
    user = User.generate!(login: 'nodev', firstname: 'No', lastname: 'Dev', password: 'NoDev1234')
    Member.create!(project: @project, user: user, roles: [role])

    log_user('nodev', 'NoDev1234')
    visit project_deployment_overview_path(@project)

    assert_text 'not authorized to access'
  end

  private

  def create_deployment(env:, status:, sha:, ref:, issues:, completed_at:, env_url: nil)
    deployment = ExternalDeployment.create!(
      provider: @repo.provider,
      external_repository: @repo,
      provider_deployment_id: "deploy-#{SecureRandom.hex(4)}",
      environment_name: env,
      environment_url: env_url,
      status: status,
      sha: sha,
      ref: ref,
      branch_name: ref,
      creator_login: 'deployer',
      started_at: completed_at.present? ? completed_at - 5.minutes : 30.minutes.ago,
      completed_at: completed_at,
      last_event_at: completed_at.presence || 10.minutes.ago
    )
    issues.each do |issue|
      ExternalDeploymentIssue.create!(external_deployment: deployment, issue: issue)
    end
    deployment
  end
end
