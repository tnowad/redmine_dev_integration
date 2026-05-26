# frozen_string_literal: true

require_relative '../../../../test/application_system_test_case'
require_relative '../support/dev_integration_test_factory'

class UserMappingTest < ApplicationSystemTestCase
  include DevIntegrationTestFactory

  def setup
    @project = Project.generate!
    @project.enable_module!(:redmine_dev_integration)
    Role.find(1).add_permission! :manage_development_integration
    Role.find(1).add_permission! :manage_provider_webhooks
    Role.find(1).add_permission! :trigger_provider_sync
    Setting.stubs(:plugin_redmine_dev_integration).returns({
      'github_provider_enabled' => '1'
    })
    log_user('admin', 'admin')
  end

  def settings_url
    "/projects/#{@project.identifier}/settings?tab=dev_integration_users"
  end

  def test_table_shows_correct_headers
    user = User.find(1)
    ExternalProviderUserMapping.create!(
      provider: 'github',
      provider_user_id: '111',
      provider_login: 'test-dev',
      user_id: user.id
    )
    visit settings_url

    within '#provider-user-mappings table.list thead' do
      assert_text 'Provider'
      assert_text 'Provider Login'
      assert_text 'Redmine User'
    end
  end

  def test_empty_state_shows_nodata_message
    visit settings_url

    within '#provider-user-mappings' do
      assert_selector 'p.nodata', text: 'No data'
    end
  end

  def test_mapping_table_uses_list_class
    user = User.find(1)
    ExternalProviderUserMapping.create!(
      provider: 'github',
      provider_user_id: '11111',
      provider_login: 'test-list-class',
      user_id: user.id
    )
    visit settings_url

    within '#provider-user-mappings' do
      assert_selector 'table.list'
    end
  end

  def test_mapping_appears_in_table
    user = User.find(1)
    ExternalProviderUserMapping.create!(
      provider: 'github',
      provider_user_id: '54321',
      provider_login: 'devuser',
      user_id: user.id
    )
    visit settings_url

    within '#provider-user-mappings table.list tbody' do
      assert_text 'github'
      assert_text 'devuser'
      assert_text user.name
    end
  end

  def test_action_column_has_buttons_class
    user = User.find(1)
    ExternalProviderUserMapping.create!(
      provider: 'github',
      provider_user_id: '99999',
      provider_login: 'testlogin',
      user_id: user.id
    )
    visit settings_url

    within '#provider-user-mappings table.list tbody' do
      assert_selector 'td.buttons'
    end
  end

  def test_delete_link_on_mapping_row_has_icon_del_class
    user = User.find(1)
    ExternalProviderUserMapping.create!(
      provider: 'github',
      provider_user_id: '11111',
      provider_login: 'icon-del-test',
      user_id: user.id
    )
    visit settings_url

    within '#provider-user-mappings table.list tbody td.buttons' do
      assert_selector 'a.icon-del'
    end
  end

  def test_delete_link_has_confirm_and_delete_method
    user = User.find(1)
    mapping = ExternalProviderUserMapping.create!(
      provider: 'github',
      provider_user_id: '22222',
      provider_login: 'deleteable',
      user_id: user.id
    )
    visit settings_url

    within '#provider-user-mappings table.list tbody td.buttons' do
      delete_link = find('a.icon-del')
      assert_equal 'delete', delete_link['data-method']
      assert delete_link['data-confirm'].present?
    end
  end

  def test_add_form_is_inside_fieldset_box_tabular
    visit settings_url

    assert_selector 'fieldset#add-mapping-form.box.tabular'
  end

  def test_submit_button_says_add
    visit settings_url

    within '#add-mapping-form' do
      assert_selector "input[type='submit'][value='Add']"
    end
  end

  def test_add_form_has_required_fields
    visit settings_url

    within '#add-mapping-form' do
      assert_selector "input#mapping_provider_user_id"
      assert_selector "input#mapping_provider_login"
      assert_selector "select#mapping_user_id"
      assert_selector "select#mapping_provider"
    end
  end

  def test_add_form_provider_select_has_github_and_gitlab_options
    visit settings_url

    within '#add-mapping-form' do
      within 'select#mapping_provider' do
        assert_selector "option[value='github']"
        assert_selector "option[value='gitlab']"
      end
    end
  end

  def test_fill_add_mapping_form_fields
    user = User.find(1)
    visit settings_url

    within '#add-mapping-form' do
      select 'GitHub', from: 'mapping_provider'
      fill_in 'mapping_provider_user_id', with: '12345'
      fill_in 'mapping_provider_login', with: 'octocat'
      select user.name, from: 'mapping_user_id'
    end

    assert_equal 'github', find('#mapping_provider').value
    assert_equal '12345', find('#mapping_provider_user_id').value
    assert_equal 'octocat', find('#mapping_provider_login').value
    assert_equal user.id.to_s, find('#mapping_user_id').value
  end

  def test_nodata_message_hidden_when_mappings_exist
    user = User.find(1)
    ExternalProviderUserMapping.create!(
      provider: 'github',
      provider_user_id: '33333',
      provider_login: 'existing-user',
      user_id: user.id
    )
    visit settings_url

    within '#provider-user-mappings' do
      refute_selector 'p.nodata'
    end
  end

  def test_multiple_mappings_display_in_table
    user = User.find(1)
    ExternalProviderUserMapping.create!(
      provider: 'github',
      provider_user_id: '44444',
      provider_login: 'user-one',
      user_id: user.id
    )
    ExternalProviderUserMapping.create!(
      provider: 'gitlab',
      provider_user_id: '55555',
      provider_login: 'user-two',
      user_id: user.id
    )
    visit settings_url

    within '#provider-user-mappings table.list tbody' do
      assert_text 'user-one'
      assert_text 'user-two'
    end
  end

  def test_delete_link_generates_project_redmine_dev_integration_path
    user = User.find(1)
    mapping = ExternalProviderUserMapping.create!(
      provider: 'github',
      provider_user_id: '66666',
      provider_login: 'route-test',
      user_id: user.id
    )
    visit settings_url

    within '#provider-user-mappings table.list tbody td.buttons' do
      delete_link = find('a.icon-del')
      expected_path = "/projects/#{@project.identifier}/redmine_dev_integration"
      assert_includes delete_link['href'], expected_path
    end
  end
end
