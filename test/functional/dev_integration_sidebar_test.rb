# frozen_string_literal: true

require_relative '../test_helper'

class DevIntegrationSidebarTest < Redmine::ControllerTest
  tests IssuesController
  fixtures :projects, :issues, :users, :roles, :members, :member_roles, :enabled_modules, :repositories

  def setup
    super
    @project = projects(:projects_001)
    @project.update_columns(issue_key_prefix: 'SIDEBAR')
    @project.enable_module!(:redmine_dev_integration)
    @issue = issues(:issues_001)
    @issue.update_columns(issue_key: 'SIDEBAR-1')
    @repository = repositories(:repositories_001)
    @repository.update_columns(project_id: @project.id)
    @external_repository = ExternalRepository.create!(
      provider: 'github',
      provider_repository_id: '999',
      owner: 'redmine',
      repo_name: 'sidebar_repo',
      full_name: 'redmine/sidebar_repo',
      url: 'https://github.com/redmine/sidebar_repo',
      redmine_project: @project,
      redmine_repository: @repository
    )
  end

  def test_sidebar_shows_dev_counts_when_data_exists
    @request.session[:user_id] = 1

    branch = ExternalBranch.create!(
      external_repository: @external_repository,
      name: 'feature/sidebar',
      url: 'https://github.com/redmine/sidebar_repo/tree/feature/sidebar',
      sha: 'abc123',
      state: 'active'
    )
    branch.link_issues_from_texts(@issue.issue_key)

    pr = ExternalPullRequest.create!(
      provider: 'github',
      external_repository: @external_repository,
      number: 1,
      title: 'Sidebar widget PR',
      body: nil,
      url: 'https://github.com/redmine/sidebar_repo/pull/1',
      state: 'open',
      merged: false
    )
    pr.link_issues_from_texts(@issue.issue_key)

    get :show, params: { id: @issue.id }

    assert_response :success
    assert_select '.box h3', text: /Development/
    assert_select '.box li', text: /Branch: 1/
    assert_select '.box li', text: /Pull requests: 1/
  end

  def test_sidebar_hidden_when_no_dev_data
    @request.session[:user_id] = 1

    get :show, params: { id: @issue.id }

    assert_response :success
    assert_select '.box h3', text: /Development/, count: 0
  end

  def test_sidebar_hidden_when_user_lacks_permission
    @request.session[:user_id] = nil

    branch = ExternalBranch.create!(
      external_repository: @external_repository,
      name: 'feature/sidebar',
      url: 'https://github.com/redmine/sidebar_repo/tree/feature/sidebar',
      sha: 'abc123',
      state: 'active'
    )
    branch.link_issues_from_texts(@issue.issue_key)

    get :show, params: { id: @issue.id }

    assert_response :success
    assert_select '.box h3', text: /Development/, count: 0
  end

  def test_sidebar_hidden_when_setting_disables_panel
    @request.session[:user_id] = 1

    branch = ExternalBranch.create!(
      external_repository: @external_repository,
      name: 'feature/sidebar',
      url: 'https://github.com/redmine/sidebar_repo/tree/feature/sidebar',
      sha: 'abc123',
      state: 'active'
    )
    branch.link_issues_from_texts(@issue.issue_key)

    Project.any_instance.stubs(:development_integration_project_setting).returns(
      Struct.new(:show_dev_panel).new(false)
    )

    get :show, params: { id: @issue.id }

    assert_response :success
    assert_select '.box h3', text: /Development/, count: 0
  end

  def test_sidebar_shows_development_heading_with_all_data_types
    @request.session[:user_id] = 1

    branch = ExternalBranch.create!(
      external_repository: @external_repository,
      name: 'feature/sidebar',
      url: 'https://github.com/redmine/sidebar_repo/tree/feature/sidebar',
      sha: 'abc123',
      state: 'active'
    )
    branch.link_issues_from_texts(@issue.issue_key)

    pr = ExternalPullRequest.create!(
      provider: 'github',
      external_repository: @external_repository,
      number: 42,
      title: 'PR',
      body: nil,
      url: 'https://github.com/redmine/sidebar_repo/pull/42',
      state: 'open',
      merged: true
    )
    pr.link_issues_from_texts(@issue.issue_key)

    ec = ExternalCommit.create!(
      provider: 'github',
      external_repository: @external_repository,
      provider_commit_id: 'sha123',
      sha: 'sha1234567890abc',
      short_sha: 'sha12345',
      message: 'Commit message',
      author_login: 'dev',
      author_name: 'Dev',
      url: 'https://github.com/redmine/sidebar_repo/commit/sha1234567890abc',
      branch_name: 'main',
      committed_at: Time.current,
      last_event_at: Time.current
    )
    ec.link_issues_from_texts(@issue.issue_key)

    build = ExternalBuild.create!(
      provider: 'github',
      external_repository: @external_repository,
      provider_build_id: 'b101',
      build_number: 101,
      name: 'Build',
      status: 'success',
      url: 'https://github.com/redmine/sidebar_repo/actions/runs/101',
      sha: 'sha1234567890abc',
      ref: 'main',
      started_at: Time.current,
      finished_at: Time.current,
      last_event_at: Time.current
    )
    build.link_issues_from_texts(@issue.issue_key)

    depl = ExternalDeployment.create!(
      provider: 'github',
      external_repository: @external_repository,
      provider_deployment_id: 'd301',
      environment_name: 'production',
      environment_url: 'https://prod.example.test',
      status: 'success',
      sha: 'sha1234567890abc',
      ref: 'main',
      started_at: Time.current,
      completed_at: Time.current,
      last_event_at: Time.current
    )
    depl.link_issues_from_texts(@issue.issue_key)

    get :show, params: { id: @issue.id }

    assert_response :success
    assert_select '.box h3', text: /Development/
    assert_select '.box li', text: /Branch: 1/
    assert_select '.box li', text: /Pull requests: 1/
    assert_select '.box li', text: /Revisions: 1/
    assert_select '.box li', text: /Builds: 1/
    assert_select '.box li', text: /Deployments: 1/
  end
end
