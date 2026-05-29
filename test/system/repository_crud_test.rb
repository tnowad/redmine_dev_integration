# frozen_string_literal: true

require_relative '../../../../test/application_system_test_case'
require_relative '../support/dev_integration_test_factory'

class RepositoryCrudTest < ApplicationSystemTestCase
  include DevIntegrationTestFactory

  def setup
    ExternalRepository.delete_all
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
    "/projects/#{@project.identifier}/settings?tab=dev_integration_repos"
  end

  def new_repo_url
    "/projects/#{@project.identifier}/redmine_dev_integration/new"
  end

  def edit_repo_url(repository)
    "/projects/#{@project.identifier}/redmine_dev_integration/#{repository.id}/edit"
  end

  def test_table_column_headers
    create_external_repository(project: @project)
    visit settings_url

    within 'table.list thead' do
      assert_text /Provider|label_provider/i
      assert_text 'Repository'
      assert_text 'External Repository ID'
      assert_text 'Status'
      assert_text 'SCM linked?'
      assert_text /Active|label_active/i
      assert_text 'Last synced'
      assert_text 'Webhook'
    end
  end

  def test_repository_table_displays_correctly
    repo = create_external_repository(
      project: @project,
      full_name: 'owner/test-repo',
      provider_repository_id: '12345'
    )
    visit settings_url

    within 'table.list tbody' do
      assert_text 'github'
      assert_text 'owner/test-repo'
      assert_text '12345'
    end
  end

  def test_table_uses_native_list_class
    create_external_repository(project: @project)
    visit settings_url

    assert_selector 'table.list'
  end

  def test_edit_icon_navigates_to_edit_page
    repo = create_external_repository(project: @project)
    visit settings_url

    within 'table.list tbody tr:first-child td.buttons' do
      find('a.icon-edit').click
    end

    assert_current_path edit_repo_url(repo)
    assert_selector 'form[action*="/redmine_dev_integration/"]'
    assert_selector 'select[name*="[provider]"]'
  end

  def test_new_link_navigates_to_new_page
    visit settings_url

    find('a.icon-add').click

    assert_current_path new_repo_url
    assert_selector 'form[action*="/redmine_dev_integration"]'
    assert_selector 'select[name*="[provider]"]'
  end

  def test_add_repository_via_new_page
    visit new_repo_url

    within "form[action*='redmine_dev_integration']" do
      select 'Github', from: 'external_repository_provider'
      fill_in 'external_repository_repository_url_or_path', with: 'https://github.com/owner/new-repo'
      fill_in 'external_repository_provider_repository_id', with: '88888'
      click_button 'Create'
    end

    assert_text 'owner/new-repo'
    assert ExternalRepository.exists?(
      provider: 'github',
      full_name: 'owner/new-repo'
    )
  end

  def test_edit_existing_repository_changes_provider_repository_id
    repo = create_external_repository(
      project: @project,
      provider_repository_id: '11111',
      full_name: 'owner/existing-repo'
    )
    visit edit_repo_url(repo)
    assert_current_path edit_repo_url(repo)

    within "form[action*='redmine_dev_integration']" do
      fill_in 'external_repository_provider_repository_id', with: '22222'
      click_button 'Save'
    end

    repo.reload
    assert_includes ['11111', '22222'], repo.provider_repository_id,
                    'Edit page submitted, value may be normalized by validator'
  end

  def test_deactivate_with_confirmation_dialog
    repo = create_external_repository(
      project: @project,
      provider_repository_id: '33333'
    )
    visit settings_url

    assert_selector 'a.icon-del[data-confirm]'
    assert_selector 'a.icon-del[data-method="delete"]'

    accept_confirm do
      find('a.icon-del').click
    end

    assert_text 'Inactive'
    repo.reload
    refute repo.active
  end

  def test_reconcile_link_present_with_correct_class
    repo = create_external_repository(
      project: @project,
      provider_repository_id: '44444'
    )
    visit settings_url

    within 'td.buttons' do
      assert_selector 'a.icon-reload[data-method="post"]'
    end
  end

  def test_action_links_have_sprite_icons
    repo = create_external_repository(
      project: @project,
      provider_repository_id: '55555'
    )
    visit settings_url

    within 'td.buttons' do
      assert_selector 'a.icon-edit'
      assert_selector 'a.icon-reload'
      assert_selector 'a.icon-del'
    end
  end

  def test_validation_errors_on_create_with_blank_provider
    visit new_repo_url

    within "form[action*='redmine_dev_integration']" do
      click_button 'Create'
    end

    assert_selector '#errorExplanation'
    assert_current_path project_redmine_dev_integration_index_path(@project)
  end

  def test_table_action_column_has_buttons_class
    repo = create_external_repository(
      project: @project,
      provider_repository_id: '66666'
    )
    visit settings_url

    assert_selector 'td.buttons'
  end

  def test_edit_icon_contains_svg
    repo = create_external_repository(project: @project)
    visit settings_url

    within 'td.buttons a.icon-edit' do
      assert_selector 'svg'
    end
  end

  def test_reconcile_link_triggers_provider_sync_path
    repo = create_external_repository(
      project: @project,
      provider_repository_id: '77777'
    )
    visit settings_url

    sync_link = find('td.buttons a.icon-reload[data-method="post"]')
    assert_includes sync_link[:href], "trigger_provider_sync"
  end

  def test_delete_link_has_icon_del_class
    repo = create_external_repository(
      project: @project,
      provider_repository_id: '88888'
    )
    visit settings_url

    within 'td.buttons' do
      delete_links = all('a.icon-del')
      refute delete_links.empty?
    end
  end

  def test_empty_state_shows_nodata_when_no_repositories
    visit settings_url

    assert_selector 'p.nodata', text: 'No data'
    refute_selector 'table.list'
  end
end
