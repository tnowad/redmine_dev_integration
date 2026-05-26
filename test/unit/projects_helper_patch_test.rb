# frozen_string_literal: true

require_relative '../test_helper'

class ProjectsHelperPatchTest < Redmine::HelperTest
  include ProjectsHelper

  def setup
    super
    @project = projects(:projects_001)
    @project.enable_module!(:redmine_dev_integration)
  end

  def test_project_settings_tabs_includes_dev_integration_tabs_for_view_permission
    User.current = users(:users_001)

    tab_names = project_settings_tabs.map {|tab| tab[:name]}

    assert_includes tab_names, 'dev_integration_settings'
    assert_includes tab_names, 'dev_integration_repos'
    assert_includes tab_names, 'dev_integration_events'
    assert_includes tab_names, 'dev_integration_users'
  end

  def test_project_settings_tabs_excludes_dev_integration_tabs_without_permission
    User.current = User.anonymous

    tab_names = project_settings_tabs.map {|tab| tab[:name]}

    assert_not_includes tab_names, 'dev_integration_settings'
    assert_not_includes tab_names, 'dev_integration_repos'
    assert_not_includes tab_names, 'dev_integration_events'
    assert_not_includes tab_names, 'dev_integration_users'
  end
end
