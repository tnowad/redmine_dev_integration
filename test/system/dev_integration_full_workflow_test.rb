# frozen_string_literal: true

require_relative '../../../../test/application_system_test_case'
require_relative '../support/dev_integration_test_factory'

class DevIntegrationFullWorkflowTest < ApplicationSystemTestCase
  include DevIntegrationTestFactory

  def setup
    @project = Project.generate!(identifier: 'e2e-test', name: 'E2E Test')
    @project.enable_module!(:redmine_dev_integration)
    Role.find(1).add_permission!(:manage_development_integration)
    Role.find(1).add_permission!(:manage_provider_webhooks)
    Role.find(1).add_permission!(:trigger_provider_sync)
    Role.find(1).add_permission!(:view_development_integration)
    Setting.plugin_redmine_dev_integration = {
      'github_provider_enabled' => '1',
      'github_webhook_secret' => '',
      'github_api_token' => '',
      'github_oauth_client_id' => '',
      'github_oauth_client_secret' => '',
      'github_oauth_connected_at' => '',
      'github_oauth_access_token' => '',
      'github_oauth_refresh_token' => '',
      'github_oauth_token_expires_at' => '',
      'gitlab_provider_enabled' => '1',
      'gitlab_webhook_token' => '',
      'gitlab_api_token' => '',
      'gitlab_base_url' => '',
      'gitlab_oauth_app_id' => '',
      'gitlab_oauth_app_secret' => '',
      'gitlab_oauth_connected_at' => '',
      'gitlab_oauth_access_token' => '',
      'gitlab_oauth_refresh_token' => '',
      'gitlab_oauth_token_expires_at' => '',
      'bitbucket_provider_enabled' => '1',
      'bitbucket_webhook_secret' => '',
      'bitbucket_api_token' => ''
    }
  end

  test "admin configures plugin settings" do
    log_user('admin', 'admin')
    visit '/settings/plugin/redmine_dev_integration'

    assert_text 'Redmine Dev Integration'

    find("input#settings_github_provider_enabled").set(true)
    find("input#settings_github_webhook_secret").set('test-webhook-secret')
    find("input#settings_github_api_token").set('test-api-token')

    click_button 'Apply'

    assert_text 'Successful update.'

    visit '/settings/plugin/redmine_dev_integration'
    assert_selector 'em.info', text: 'configured'
  end

  test "admin configures oauth credentials and sees connect link" do
    log_user('admin', 'admin')
    visit '/settings/plugin/redmine_dev_integration'

    find("input#settings_github_oauth_client_id").set('test-client-id')
    find("input#settings_github_oauth_client_secret").set('test-client-secret')

    click_button 'Apply'

    assert_text 'Successful update.'

    visit '/settings/plugin/redmine_dev_integration'
    assert_selector "a.icon-add[href*='github/oauth/start']"
  end

  test "admin navigates to project settings repos tab" do
    log_user('admin', 'admin')
    visit settings_project_path(@project, tab: 'dev_integration_repos')

    assert_selector 'a.icon-add'
    assert_selector 'p.nodata', text: 'No data'
  end

  test "admin adds repository via new page" do
    log_user('admin', 'admin')
    visit new_project_redmine_dev_integration_path(@project)

    within "form[action*='redmine_dev_integration']" do
      select 'GitHub', from: 'external_repository_provider'
      fill_in 'external_repository_repository_url_or_path', with: 'owner/repo'
      fill_in 'external_repository_provider_repository_id', with: '12345'
      click_button 'Create'
    end

    assert_text 'owner/repo'
  end

  test "repository appears in table with correct columns" do
    repo = create_external_repository(project: @project, provider: 'github', full_name: 'owner/repo', provider_repository_id: '12345')

    log_user('admin', 'admin')
    visit settings_project_path(@project, tab: 'dev_integration_repos')

    within 'table.list' do
      assert_text 'owner/repo'
      assert_text '12345'
      assert_text 'github'
    end
  end

  test "admin deactivates repository" do
    repo = create_external_repository(project: @project, provider: 'github', full_name: 'owner/repo', provider_repository_id: '12345')

    log_user('admin', 'admin')
    visit settings_project_path(@project, tab: 'dev_integration_repos')

    page.accept_confirm do
      find("a[data-method='delete'][href*='#{project_redmine_dev_integration_path(@project, repo)}']").click
    end

    assert_text 'Inactive'
  end

  test "admin edits repository on separate edit page" do
    repo = create_external_repository(project: @project, provider: 'github', full_name: 'owner/repo', provider_repository_id: '12345')

    log_user('admin', 'admin')
    visit edit_project_redmine_dev_integration_path(@project, repo)

    within "form[action*='redmine_dev_integration']" do
      fill_in 'external_repository_provider_repository_id', with: '99999'
      click_button 'Save'
    end

    assert_text '99999'
  end

  test "admin registers webhook" do
    repo = create_external_repository(project: @project, provider: 'github', full_name: 'owner/repo', provider_repository_id: '12345')

    Setting.plugin_redmine_dev_integration = Setting.plugin_redmine_dev_integration.merge(
      'github_webhook_secret' => 'test-webhook-secret',
      'github_api_token' => 'test-api-token'
    )

    RedmineDevIntegration::ProviderClients::GitHubClient.any_instance.stubs(:list_webhooks).returns([])
    RedmineDevIntegration::ProviderClients::GitHubClient.any_instance.stubs(:create_webhook).returns({ 'id' => 999, 'active' => true })

    log_user('admin', 'admin')
    visit settings_project_path(@project, tab: 'dev_integration_repos')

    find("a[data-method='post'][href*='register_webhook']").click

    assert_text 'Webhook created'
    repo.reload
    assert_equal 'registered', repo.webhook_registration_status
    assert_equal '999', repo.provider_webhook_id
  end

  test "provider events table visible with retry button for failed events" do
    repo = create_external_repository(project: @project, provider: 'github', full_name: 'owner/repo', provider_repository_id: '12345')

    ExternalProviderEvent.create!(
      provider: 'github',
      delivery_id: 'delivery-failed-001',
      event_type: 'push',
      payload: JSON.generate({repository: {id: 12345}}),
      status: 'failed',
      processed_at: 1.hour.ago,
      error_message: 'Something went wrong'
    )

    ExternalProviderEvent.create!(
      provider: 'github',
      delivery_id: 'delivery-success-001',
      event_type: 'push',
      payload: JSON.generate({repository: {id: 12345}}),
      status: 'processed',
      processed_at: 30.minutes.ago
    )

    log_user('admin', 'admin')
    visit settings_project_path(@project, tab: 'dev_integration_events')

    assert_selector 'fieldset#provider-events'
    assert_text 'delivery-failed-001'
    assert_text 'delivery-success-001'
    assert_selector "a.icon-reload[href*='retry_provider_event']"
  end

  test "admin enables automation settings" do
    log_user('admin', 'admin')
    visit settings_project_path(@project, tab: 'dev_integration_settings')

    check 'development_integration_project_setting_automation_enabled'
    select IssueStatus.find(2).name, from: 'development_integration_project_setting_branch_created_status_id'
    select IssueStatus.find(3).name, from: 'development_integration_project_setting_pr_opened_status_id'
    select IssueStatus.find(4).name, from: 'development_integration_project_setting_pr_merged_status_id'
    check 'development_integration_project_setting_pr_closed_note_enabled'
    check 'development_integration_project_setting_show_builds'
    check 'development_integration_project_setting_show_deployments'
    check 'development_integration_project_setting_build_failed_note_enabled'

    click_button 'Save'

    assert_text 'Successful update.'

    setting = DevelopmentIntegrationProjectSetting.for_project(@project)
    assert setting.automation_enabled
    assert setting.show_builds
    assert setting.show_deployments
    assert setting.pr_closed_note_enabled
    assert setting.build_failed_note_enabled
  end
end
