# frozen_string_literal: true

require_relative '../../test_helper'

class Projects::ReleasesControllerTest < Redmine::ControllerTest
  fixtures :projects, :users, :roles, :members, :member_roles, :repositories

  def setup
    @request.session[:user_id] = 2
    @project = Project.find(1)
    @project.enable_module!(:redmine_dev_integration)

    @repo = ExternalRepository.create!(
      provider: 'github',
      provider_repository_id: 'releases-ctlr-test-12345',
      owner: 'redmine',
      repo_name: 'redmine',
      full_name: 'redmine/redmine',
      url: 'https://github.com/redmine/redmine',
      redmine_project: @project,
      active: true
    )

    @release = ExternalRelease.create!(
      provider: 'github',
      external_repository: @repo,
      name: 'v1.0.0',
      tag_name: 'v1.0.0',
      status: 'published',
      body: 'Release notes',
      url: 'https://github.com/redmine/redmine/releases/tag/v1.0.0',
      author_login: 'contributor',
      released_at: Time.current
    )
  end

  def test_index_returns_success
    Role.find(1).add_permission! :view_development_integration
    get :index, params: { project_id: @project.identifier }
    assert_response :success
  end

  def test_index_includes_published_releases
    Role.find(1).add_permission! :view_development_integration
    draft = ExternalRelease.create!(
      provider: 'github',
      external_repository: @repo,
      name: 'v2.0.0-draft',
      tag_name: 'v2.0.0',
      status: 'draft'
    )

    get :index, params: { project_id: @project.identifier }
    assert_response :success
    assert_includes response.body, @release.name
    assert_not_includes response.body, draft.name
  end

  def test_index_shows_releases_for_active_repos_only
    Role.find(1).add_permission! :view_development_integration
    inactive_repo = ExternalRepository.create!(
      provider: 'gitlab',
      provider_repository_id: 'releases-ctlr-inactive-999',
      owner: 'other',
      repo_name: 'other',
      full_name: 'other/other',
      url: 'https://gitlab.com/other/other',
      redmine_project: @project,
      active: false
    )
    inactive_release = ExternalRelease.create!(
      provider: 'gitlab',
      external_repository: inactive_repo,
      name: 'v3.0.0',
      tag_name: 'v3.0.0',
      status: 'published'
    )

    get :index, params: { project_id: @project.identifier }
    assert_response :success
    assert_includes response.body, @release.name
    assert_not_includes response.body, inactive_release.name
  end
end
