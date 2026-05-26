# frozen_string_literal: true

require_relative '../test_helper'

class IssuesControllerPatchTest < Redmine::ControllerTest
  tests IssuesController
  fixtures :projects, :issues, :users, :roles, :members, :member_roles, :enabled_modules, :repositories, :changesets

  def setup
    super
    @project = projects(:projects_001)
    @project.enable_module!(:redmine_dev_integration)
    @issue = issues(:issues_001)
  end

  def test_show_displays_development_tab_with_permission
    @request.session[:user_id] = 1

    get :show, params: {id: @issue.id}

    assert_response :success
    assert_select '#history a[id=?]', 'tab-development', text: /Development/
  end

  def test_show_displays_development_tab_by_default_without_setting
    @request.session[:user_id] = 1

    Project.any_instance.stubs(:development_integration_project_setting).returns(nil)
    get :show, params: {id: @issue.id}

    assert_response :success
    assert_select '#history a[id=?]', 'tab-development', text: /Development/
  end

  def test_show_hides_development_tab_without_permission
    @request.session[:user_id] = nil

    get :show, params: {id: @issue.id}

    assert_response :success
    assert_select '#history a[id=?]', 'tab-development', 0
  end

  def test_show_hides_development_tab_when_setting_disables_panel
    @request.session[:user_id] = 1

    Project.any_instance.stubs(:development_integration_project_setting).returns(
      Struct.new(:show_dev_panel).new(false)
    )
    get :show, params: {id: @issue.id}

    assert_response :success
    assert_select '#history a[id=?]', 'tab-development', 0
  end

  def test_issue_tab_renders_development_partial_empty_state
    @request.session[:user_id] = 1

    get :issue_tab, params: {id: @issue.id, name: 'development', format: 'js'}, xhr: true

    assert_response :success
    assert_select 'div.development-panel' do
      assert_select 'section.development-panel-section', 5
      assert_select 'p.nodata', 5
    end
  end

  def test_issue_tab_rejects_when_setting_disables_panel
    @request.session[:user_id] = 1

    Project.any_instance.stubs(:development_integration_project_setting).returns(
      Struct.new(:show_dev_panel).new(false)
    )
    get :issue_tab, params: {id: @issue.id, name: 'development', format: 'js'}, xhr: true

    assert_response :forbidden
  end

  def test_issue_tab_hides_builds_and_deployments_when_settings_disable_them
    @request.session[:user_id] = 1

    Project.any_instance.stubs(:development_integration_project_setting).returns(
      Struct.new(:show_dev_panel, :show_builds, :show_deployments).new(true, false, false)
    )

    get :issue_tab, params: {id: @issue.id, name: 'development', format: 'js'}, xhr: true

    assert_response :success
    assert_select 'div.development-panel' do
      assert_select 'section.development-panel-section', 3
      assert_select 'h3', text: 'Builds', count: 0
      assert_select 'h3', text: 'Deployments', count: 0
    end
  end

  def test_issue_tab_renders_associated_revisions_without_updated_on_dependency
    @request.session[:user_id] = 1
    issue = issues(:issues_001)
    changeset = changesets(:changesets_001)
    issue.changesets << changeset unless issue.changesets.exists?(changeset.id)

    get :issue_tab, params: {id: issue.id, name: 'development', format: 'js'}, xhr: true

    assert_response :success
    assert_select 'div.development-panel' do
      assert_select 'h3', text: /Revisions/
      assert_select 'div.changeset.journal'
      assert_select 'div.changeset-comments'
    end
  end

  def test_issue_tab_renders_development_partial_with_metadata_and_links
    @request.session[:user_id] = 1

    project = Project.generate!(issue_key_prefix: 'DEV')
    project.enable_module!(:redmine_dev_integration)
    issue = Issue.generate!(project: project, subject: 'Development panel issue')
    repository = repositories(:repositories_001)
    external_repository = ExternalRepository.create!(
      provider: 'github',
      provider_repository_id: '123',
      owner: 'redmine',
      repo_name: 'redmine_dev_integration',
      full_name: 'redmine/redmine_dev_integration',
      url: 'https://github.com/redmine/redmine_dev_integration',
      redmine_project: project
    )

    branch = ExternalBranch.create!(
      external_repository: external_repository,
      name: 'main',
      url: 'https://github.com/redmine/redmine_dev_integration/tree/main',
      sha: 'abc123',
      state: 'active',
      updated_at: Time.zone.parse('2026-05-25T10:00:00Z')
    )
    branch.link_issues_from_texts(issue.issue_key)

    external_commit = ExternalCommit.create!(
      provider: 'github',
      external_repository: external_repository,
      provider_commit_id: 'abc123def456',
      sha: 'abc123def4567890',
      short_sha: 'abc123d',
      message: 'Follow tracked issue',
      author_login: 'contributor',
      author_name: 'Contributor',
      url: 'https://github.com/redmine/redmine_dev_integration/commit/abc123def456',
      branch_name: 'main',
      committed_at: Time.zone.parse('2026-05-25T08:30:00Z'),
      last_event_at: Time.zone.parse('2026-05-25T08:30:00Z')
    )
    external_commit.link_issues_from_texts(issue.issue_key)

    pull_request = ExternalPullRequest.create!(
      provider: 'github',
      external_repository: external_repository,
      number: 7,
      title: 'Fix tracked issue',
      body: nil,
      url: 'https://github.com/redmine/redmine_dev_integration/pull/7',
      state: 'open',
      author_login: 'contributor',
      source_branch: 'feature/auth-15c',
      target_branch: 'main',
      merged: true,
      last_event_at: Time.zone.parse('2026-05-25T11:30:00Z')
    )
    pull_request.link_issues_from_texts(issue.issue_key)

    build = ExternalBuild.create!(
      provider: 'github',
      external_repository: external_repository,
      provider_build_id: '101',
      build_number: 101,
      name: 'Build 101',
      status: 'success',
      url: 'https://github.com/redmine/redmine_dev_integration/actions/runs/101',
      sha: '0123456789abcdef',
      ref: 'main',
      started_at: Time.zone.parse('2026-05-25T09:00:00Z'),
      finished_at: Time.zone.parse('2026-05-25T09:15:00Z'),
      last_event_at: Time.zone.parse('2026-05-25T09:15:00Z')
    )
    build.link_issues_from_texts(issue.issue_key)

    deployment = ExternalDeployment.create!(
      provider: 'github',
      external_repository: external_repository,
      provider_deployment_id: '201',
      environment_name: 'staging',
      environment_url: 'https://staging.example.test',
      status: 'success',
      sha: 'fedcba9876543210',
      ref: 'release/1.0',
      started_at: Time.zone.parse('2026-05-25T10:00:00Z'),
      completed_at: Time.zone.parse('2026-05-25T10:30:00Z'),
      last_event_at: Time.zone.parse('2026-05-25T10:30:00Z')
    )
    deployment.link_issues_from_texts(issue.issue_key)

    get :issue_tab, params: {id: issue.id, name: 'development', format: 'js'}, xhr: true

    assert_response :success
    assert_select 'div.development-panel' do
      assert_select 'section.development-panel-section', 5
      assert_select 'div.changeset.journal'
      assert_select 'h3', text: /Revisions/
      assert_select 'h3', text: 'Builds'
      assert_select 'h3', text: 'Deployments'
      assert_select 'a.icon-only.icon-link[target=?]', '_blank'
      assert_select 'div[id=?]', "external-commit-#{external_commit.id}"
      assert_select 'div[id=?]', "branch-#{branch.id}"
      assert_select 'div[id=?]', "build-#{build.id}"
      assert_select 'div[id=?]', "deployment-#{deployment.id}"
      assert_select 'div[id=?]', "pr-#{pull_request.id}"
    end
  end
end
