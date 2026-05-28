# frozen_string_literal: true

require_relative '../test_helper'

class RedmineDevIntegrationPartialTest < ActionView::TestCase
  fixtures :projects, :repositories, :issue_statuses

  def setup
    super
    @project = projects(:projects_001)
    @project.enable_module!(:redmine_dev_integration)
    Role.find(1).add_permission! :manage_development_integration
    Role.find(1).add_permission! :manage_provider_webhooks
    Role.find(1).add_permission! :trigger_provider_sync
    User.current = users(:users_001)
  end

  def teardown
    User.current = User.anonymous
  end

  def test_repos_partial_renders_read_only_table_with_new_link
    ExternalRepository.where(redmine_project: @project).delete_all
    @external_repositories = [mapped_repository, inactive_repository]

    render partial: 'projects/settings/dev_integration_repos'

    assert_select 'a.icon-add, a.icon[href*="/redmine_dev_integration/new"]'
    assert_select 'table.list'
    assert_select 'table.list th', text: /label_provider|Provider/
    assert_select 'table.list th', text: 'Repository'
    assert_select 'table.list th', text: 'External Repository ID'
    assert_select 'table.list th', text: 'Status'
    assert_select 'table.list th', text: 'SCM linked?'
    assert_select 'table.list th', text: /label_active|Active/
    assert_select 'table.list th', text: 'Last synced'
    assert_select 'table.list th', text: 'Webhook'
    assert_select 'a[href=?]', 'https://github.com/redmine/redmine_dev_integration'
    assert_select 'a.icon-edit'
    assert_select 'a.icon-reload'
    assert_select 'a.icon-del'
    assert_select 'button[type=submit][value=Validate]', count: 0
    assert_select 'form select[name=?]', 'external_repository[provider]', count: 0
    assert_select 'p.nodata', count: 0
  end

  def test_repos_partial_shows_empty_state_with_no_repositories
    ExternalRepository.where(redmine_project: @project).delete_all
    @external_repositories = []

    render partial: 'projects/settings/dev_integration_repos'

    assert_select 'a.icon-add, a.icon[href*="/redmine_dev_integration/new"]'
    assert_select 'p.nodata', text: /No data/
    assert_select 'table.list', count: 0
  end

  def test_settings_partial_renders_settings_form
    render partial: 'projects/settings/dev_integration_settings'

    assert_select 'form[action=?][method=?]', settings_project_redmine_dev_integration_index_path(@project), 'post'
    assert_select 'input[type=checkbox][name=?]', 'development_integration_project_setting[show_dev_panel]'
    assert_select 'input[type=checkbox][name=?]', 'development_integration_project_setting[automation_enabled]'
    assert_select 'input[type=checkbox][name=?]', 'development_integration_project_setting[smart_commits_enabled]'
    assert_select 'select[name=?]', 'development_integration_project_setting[branch_created_status_id]'
    assert_select 'select[name=?]', 'development_integration_project_setting[pr_opened_status_id]'
    assert_select 'select[name=?]', 'development_integration_project_setting[pr_merged_status_id]'
    assert_select 'input[type=checkbox][name=?]', 'development_integration_project_setting[pr_closed_note_enabled]'
    assert_select 'input[type=checkbox][name=?]', 'development_integration_project_setting[show_builds]'
    assert_select 'input[type=checkbox][name=?]', 'development_integration_project_setting[show_deployments]'
    assert_select 'input[type=checkbox][name=?]', 'development_integration_project_setting[build_failed_note_enabled]'
    assert_select 'select[name=?]', 'development_integration_project_setting[build_success_status_id]'
    assert_select 'select[name=?]', 'development_integration_project_setting[deployment_staging_success_status_id]'
    assert_select 'select[name=?]', 'development_integration_project_setting[deployment_production_success_status_id]'
    assert_select 'input[type=checkbox][name=?]', 'development_integration_project_setting[deployment_failed_note_enabled]'
    assert_select 'select[name=?]', 'development_integration_project_setting[deployment_failed_status_id]'
    assert_select 'input[type=submit][value=?]', 'Save'
    assert_select 'a.icon-summary'
  end

  def test_events_partial_filters_unrelated_and_unparseable_events
    repositories = [mapped_repository, inactive_repository]
    create_provider_events

    render partial: 'projects/settings/dev_integration_events', locals: {
      project: @project,
      repositories: repositories
    }

    assert_select 'fieldset#provider-events legend', text: 'Provider Events'
    assert_select 'fieldset#provider-events table.list tbody tr', 4
    assert_select 'fieldset#provider-events a.icon-reload', count: 1
    assert_select 'fieldset#provider-events td', text: 'delivery-ignored'
    assert_no_match(/delivery-foreign/, rendered)
    assert_no_match(/delivery-invalid/, rendered)
  end

  private

  def mapped_repository
    @mapped_repository ||= ExternalRepository.create!(
      provider: 'github',
      provider_repository_id: '123',
      owner: 'redmine',
      repo_name: 'redmine_dev_integration',
      full_name: 'redmine/redmine_dev_integration',
      url: 'https://github.com/redmine/redmine_dev_integration',
      redmine_project: @project,
      redmine_repository: repositories(:repositories_001),
      active: true
    )
  end

  def inactive_repository
    @inactive_repository ||= ExternalRepository.create!(
      provider: 'gitlab',
      provider_repository_id: '456',
      owner: 'redmine',
      repo_name: 'inactive_repo',
      full_name: 'redmine/inactive_repo',
      url: 'https://gitlab.com/redmine/inactive_repo',
      redmine_project: @project,
      active: false,
      last_synced_at: Time.utc(2026, 5, 26, 3, 4, 5)
    )
  end

  def create_provider_events
    ExternalProviderEvent.create!(
      provider: 'github',
      delivery_id: 'delivery-failed',
      event_type: 'push',
      payload: JSON.generate({repository: {id: 123}}),
      provider_repository_id: '123',
      status: 'failed',
      processed_at: Time.utc(2026, 5, 26, 1, 2, 3),
      error_message: 'RuntimeError: boom'
    )
    ExternalProviderEvent.create!(
      provider: 'github',
      delivery_id: 'delivery-processed',
      event_type: 'pull_request',
      payload: JSON.generate({repository: {id: 123}}),
      provider_repository_id: '123',
      status: 'processed',
      processed_at: Time.utc(2026, 5, 26, 1, 5, 0)
    )
    ExternalProviderEvent.create!(
      provider: 'gitlab',
      delivery_id: 'delivery-pending',
      event_type: 'Pipeline Hook',
      payload: JSON.generate({project: {id: 456}}),
      provider_repository_id: '456',
      status: 'pending'
    )
    ExternalProviderEvent.create!(
      provider: 'gitlab',
      delivery_id: 'delivery-ignored',
      event_type: 'Merge Request Hook',
      payload: JSON.generate({project: {id: 456}}),
      provider_repository_id: '456',
      status: 'ignored'
    )
    ExternalProviderEvent.create!(
      provider: 'github',
      delivery_id: 'delivery-foreign',
      event_type: 'push',
      payload: JSON.generate({repository: {id: 999}}),
      provider_repository_id: '999',
      status: 'failed'
    )
    ExternalProviderEvent.create!(
      provider: 'github',
      delivery_id: 'delivery-invalid',
      event_type: 'push',
      payload: '{invalid json',
      status: 'failed'
    )
  end
end
