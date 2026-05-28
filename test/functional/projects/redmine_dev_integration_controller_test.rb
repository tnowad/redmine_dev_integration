# frozen_string_literal: true

require_relative '../../test_helper'

class Projects::RedmineDevIntegrationControllerTest < Redmine::ControllerTest
  include ActiveJob::TestHelper

  fixtures :projects, :repositories, :users, :members, :member_roles, :roles, :issue_statuses

  def setup
    super
    @project = projects(:projects_001)
    @project.enable_module!(:redmine_dev_integration)
    Role.find(1).add_permission! :manage_development_integration
    Role.find(1).add_permission! :manage_provider_webhooks
    Role.find(1).add_permission! :trigger_provider_sync
    Role.find(1).add_permission! :view_development_integration
    @request.session[:user_id] = 2
    @original_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    clear_enqueued_jobs
  end

  def teardown
    clear_enqueued_jobs
    ActiveJob::Base.queue_adapter = @original_queue_adapter
    super
  end

  def test_new_renders_form
    stub_github_enabled

    get :new, params: {project_id: @project.identifier}

    assert_response :success
    assert_select 'form[action=?]', project_redmine_dev_integration_index_path(@project)
    assert_select 'select[name=?]', 'external_repository[provider]'
    assert_select 'input[type=submit][value=?]', 'Create'
  end

  def test_edit_renders_form
    stub_github_enabled
    repository = ExternalRepository.create!(valid_attributes.merge(redmine_project: @project))

    get :edit, params: {project_id: @project.identifier, id: repository.id}

    assert_response :success
    assert_select 'form[action=?]', project_redmine_dev_integration_path(@project, repository)
    assert_select 'select[name=?]', 'external_repository[provider]'
    assert_select 'input[type=submit][value=?]', 'Save'
  end

  def test_create_success
    stub_github_enabled
    capture_repository_audits do |audit_calls|
      assert_difference 'ExternalRepository.count', 1 do
        post :create, params: {project_id: @project.identifier, external_repository: valid_attributes}
      end

      assert_equal %i[connected scm_linked], audit_calls.map { |call| call[:action] }
    end

    assert_redirected_to settings_project_path(@project, tab: 'dev_integration_repos')
    repository = ExternalRepository.order(:id).last
    assert_equal 'github', repository.provider
    assert_equal @project.id, repository.redmine_project_id
    assert_equal true, repository.active
  end

  def test_create_derives_repository_metadata_from_quick_connect_input
    stub_github_enabled
    attributes = valid_attributes.merge(
      repository_url_or_path: 'git@github.com:redmine/redmine_dev_integration.git',
      owner: nil,
      repo_name: nil,
      full_name: nil,
      url: nil
    )

    capture_repository_audits do
      assert_difference 'ExternalRepository.count', 1 do
        post :create, params: {project_id: @project.identifier, external_repository: attributes}
      end
    end

    repository = ExternalRepository.order(:id).last
    assert_equal 'redmine', repository.owner
    assert_equal 'redmine_dev_integration', repository.repo_name
    assert_equal 'redmine/redmine_dev_integration', repository.full_name
    assert_equal 'https://github.com/redmine/redmine_dev_integration', repository.url
  end

  def test_create_denied_without_permission
    @request.session[:user_id] = 3

    assert_no_difference 'ExternalRepository.count' do
      post :create, params: {project_id: @project.identifier, external_repository: valid_attributes}
    end

    assert_response :forbidden
  end

  def test_create_failure_renders_new_with_errors
    stub_github_disabled

    assert_no_difference 'ExternalRepository.count' do
      post :create, params: {project_id: @project.identifier, external_repository: valid_attributes}
    end

    assert_response :success
    assert_select '#errorExplanation'
  end

  def test_create_rejects_duplicate_provider_repository_id
    stub_github_enabled
    ExternalRepository.create!(valid_attributes.merge(redmine_project: @project))

    assert_no_difference 'ExternalRepository.count' do
      post :create, params: {project_id: @project.identifier, external_repository: valid_attributes}
    end

    assert_response :success
    assert_select '#errorExplanation'
  end

  def test_update_allows_editing_non_id_fields_on_same_repository
    stub_github_enabled
    repository = ExternalRepository.create!(valid_attributes.merge(redmine_project: @project))
    capture_repository_audits do |audit_calls|
      updated_attributes = valid_attributes.merge(
        owner: 'redmine-updated',
        repo_name: 'redmine_dev_integration_v2',
        full_name: 'redmine/redmine_dev_integration_v2',
        url: 'https://github.com/redmine/redmine_dev_integration_v2'
      )

      patch :update, params: {project_id: @project.identifier, id: repository.id, external_repository: updated_attributes}

      assert_equal %i[updated], audit_calls.map { |call| call[:action] }
    end

    assert_redirected_to settings_project_path(@project, tab: 'dev_integration_repos')
    repository.reload
    assert_equal 'redmine-updated', repository.owner
    assert_equal 'redmine_dev_integration_v2', repository.repo_name
    assert_equal 'redmine/redmine_dev_integration_v2', repository.full_name
    assert_equal 'https://github.com/redmine/redmine_dev_integration_v2', repository.url
    assert_equal '123', repository.provider_repository_id
  end

  def test_update_derives_repository_metadata_from_quick_connect_input_on_existing_repository
    stub_github_enabled
    repository = ExternalRepository.create!(valid_attributes.merge(redmine_project: @project))

    capture_repository_audits do
      patch :update, params: {
        project_id: @project.identifier,
        id: repository.id,
        external_repository: valid_attributes.merge(
          repository_url_or_path: 'https://github.com/redmine/redmine_dev_integration_v2',
          owner: nil,
          repo_name: nil,
          full_name: nil,
          url: nil
        )
      }
    end

    assert_redirected_to settings_project_path(@project, tab: 'dev_integration_repos')
    repository.reload
    assert_equal 'redmine', repository.owner
    assert_equal 'redmine_dev_integration_v2', repository.repo_name
    assert_equal 'redmine/redmine_dev_integration_v2', repository.full_name
    assert_equal 'https://github.com/redmine/redmine_dev_integration_v2', repository.url
    assert_equal '123', repository.provider_repository_id
  end

  def test_update_logs_scm_link_when_repository_link_is_added
    stub_github_enabled
    repository = ExternalRepository.create!(valid_attributes.except(:redmine_repository_id).merge(redmine_project: @project))
    capture_repository_audits do |audit_calls|
      patch :update, params: {
        project_id: @project.identifier,
        id: repository.id,
        external_repository: valid_attributes
      }

      assert_equal %i[updated scm_linked], audit_calls.map { |call| call[:action] }
    end

    assert_redirected_to settings_project_path(@project, tab: 'dev_integration_repos')
    assert_equal repositories(:repositories_001).id, repository.reload.redmine_repository_id
  end

  def test_update_logs_scm_unlink_when_repository_link_is_removed
    stub_github_enabled
    repository = ExternalRepository.create!(valid_attributes.merge(redmine_project: @project))
    capture_repository_audits do |audit_calls|
      patch :update, params: {
        project_id: @project.identifier,
        id: repository.id,
        external_repository: valid_attributes.merge(redmine_repository_id: nil)
      }

      assert_equal %i[updated scm_unlinked], audit_calls.map { |call| call[:action] }
    end

    assert_redirected_to settings_project_path(@project, tab: 'dev_integration_repos')
    assert_nil repository.reload.redmine_repository_id
  end

  def test_destroy_deactivates_repository_and_preserves_row
    repository = ExternalRepository.create!(valid_attributes.merge(redmine_project: @project))
    capture_repository_audits do |audit_calls|
      assert_no_difference 'ExternalRepository.count' do
        delete :destroy, params: {project_id: @project.identifier, id: repository.id}
      end

      assert_equal %i[deactivated], audit_calls.map { |call| call[:action] }
    end

    assert_redirected_to settings_project_path(@project, tab: 'dev_integration_repos')
    assert_equal false, repository.reload.active
  end

  def test_trigger_provider_sync_updates_last_synced_at_for_active_mapped_repository
    repository = ExternalRepository.create!(valid_attributes.merge(redmine_project: @project))
    reconciled_at = Time.current
    service = Object.new
    service.define_singleton_method(:call) do |project:, repository:, provider:|
      repository.update!(last_synced_at: reconciled_at)
      RedmineDevIntegration::ReconciliationService::Result.new(
        status: :reconciled,
        reason: :last_synced_at_updated,
        repository: repository.reload,
        provider: provider
      )
    end
    RedmineDevIntegration::ReconciliationService.stubs(:new).returns(service)

    post :trigger_provider_sync, params: {project_id: @project.identifier, id: repository.id}

    assert_redirected_to settings_project_path(@project, tab: 'dev_integration_repos')
    assert_not_nil repository.reload.last_synced_at
    assert_match(/last_synced_at/i, flash[:notice])
  end

  def test_trigger_provider_sync_denied_without_permission
    @request.session[:user_id] = 3
    repository = ExternalRepository.create!(valid_attributes.merge(redmine_project: @project))

    post :trigger_provider_sync, params: {project_id: @project.identifier, id: repository.id}

    assert_response :forbidden
    assert_nil repository.reload.last_synced_at
  end

  def test_retry_provider_event_requeues_failed_event
    repository = ExternalRepository.create!(valid_attributes.merge(redmine_project: @project))
    event = ExternalProviderEvent.create!(
      provider: repository.provider,
      delivery_id: 'delivery-123',
      event_type: 'push',
      payload: JSON.generate({
        repository: {id: repository.provider_repository_id.to_i}
      }),
      status: 'failed',
      processed_at: 1.hour.ago,
      error_message: 'RuntimeError: boom'
    )

    assert_enqueued_jobs 1 do
      post :retry_provider_event, params: {project_id: @project.identifier, id: event.id}
    end

    assert_redirected_to settings_project_path(@project, tab: 'dev_integration_events')
    event.reload
    assert_equal 'pending', event.status
    assert_nil event.processed_at
    assert_nil event.error_message
    assert_equal ExternalProviderEventJob, enqueued_jobs.last[:job]
    assert_equal [event.id], enqueued_jobs.last[:args]
  end

  def test_retry_provider_event_rejects_non_failed_event
    repository = ExternalRepository.create!(valid_attributes.merge(redmine_project: @project))
    event = ExternalProviderEvent.create!(
      provider: repository.provider,
      delivery_id: 'delivery-456',
      event_type: 'push',
      payload: JSON.generate({
        repository: {id: repository.provider_repository_id.to_i}
      }),
      status: 'processed',
      processed_at: Time.current
    )

    assert_no_enqueued_jobs do
      post :retry_provider_event, params: {project_id: @project.identifier, id: event.id}
    end

    assert_redirected_to settings_project_path(@project, tab: 'dev_integration_events')
    assert_equal 'processed', event.reload.status
    assert_not_nil flash[:alert]
  end

  def test_retry_provider_event_denied_without_permission
    @request.session[:user_id] = 3
    repository = ExternalRepository.create!(valid_attributes.merge(redmine_project: @project))
    event = ExternalProviderEvent.create!(
      provider: repository.provider,
      delivery_id: 'delivery-789',
      event_type: 'push',
      payload: JSON.generate({
        repository: {id: repository.provider_repository_id.to_i}
      }),
      status: 'failed'
    )

    assert_no_enqueued_jobs do
      post :retry_provider_event, params: {project_id: @project.identifier, id: event.id}
    end

    assert_response :forbidden
    assert_equal 'failed', event.reload.status
  end

  def test_update_settings_saves_project_setting
    assert_difference 'DevelopmentIntegrationProjectSetting.count', 1 do
      patch :settings, params: {
        project_id: @project.identifier,
        development_integration_project_setting: {
          show_dev_panel: '0',
          automation_enabled: '1',
          branch_created_status_id: issue_statuses(:issue_statuses_001).id,
          pr_opened_status_id: issue_statuses(:issue_statuses_002).id,
          pr_merged_status_id: issue_statuses(:issue_statuses_003).id,
          pr_closed_note_enabled: '1',
          show_builds: '0',
          show_deployments: '0',
          build_failed_note_enabled: '1',
          build_success_status_id: issue_statuses(:issue_statuses_001).id,
          deployment_staging_success_status_id: issue_statuses(:issue_statuses_002).id,
          deployment_production_success_status_id: issue_statuses(:issue_statuses_003).id,
          deployment_failed_note_enabled: '1',
          deployment_failed_status_id: issue_statuses(:issue_statuses_001).id
        }
      }
    end

    assert_redirected_to settings_project_path(@project, tab: 'dev_integration_settings')

    setting = DevelopmentIntegrationProjectSetting.for_project(@project)
    assert_equal false, setting.show_dev_panel
    assert_equal true, setting.automation_enabled
    assert_equal issue_statuses(:issue_statuses_001), setting.branch_created_status
    assert_equal issue_statuses(:issue_statuses_002), setting.pr_opened_status
    assert_equal issue_statuses(:issue_statuses_003), setting.pr_merged_status
    assert_equal true, setting.pr_closed_note_enabled
    assert_equal false, setting.show_builds
    assert_equal false, setting.show_deployments
    assert_equal true, setting.build_failed_note_enabled
    assert_equal issue_statuses(:issue_statuses_001), setting.build_success_status
    assert_equal issue_statuses(:issue_statuses_002), setting.deployment_staging_success_status
    assert_equal issue_statuses(:issue_statuses_003), setting.deployment_production_success_status
    assert_equal true, setting.deployment_failed_note_enabled
    assert_equal issue_statuses(:issue_statuses_001), setting.deployment_failed_status
  end

  def test_update_settings_denied_without_permission
    @request.session[:user_id] = 3

    assert_no_difference 'DevelopmentIntegrationProjectSetting.count' do
      patch :settings, params: {
        project_id: @project.identifier,
        development_integration_project_setting: {show_dev_panel: '0'}
      }
    end

    assert_response :forbidden
  end

  def test_create_branch_redirects_to_github
    issue = Issue.generate!(project: @project, subject: 'Fix login bug')
    repo = ExternalRepository.create!(valid_attributes.merge(redmine_project: @project))

    get :create_branch, params: {project_id: @project, issue_id: issue.id, repository_id: repo.id}

    assert_response :redirect
    assert_equal 303, response.status
    assert_match %r{github\.com/redmine/redmine_dev_integration/tree/feature/}, response.location
    assert_match %r{-fix-login-bug\b}, response.location
  end

  def test_create_branch_with_custom_prefix
    issue = Issue.generate!(project: @project, subject: 'Hotfix crash')
    repo = ExternalRepository.create!(valid_attributes.merge(redmine_project: @project))

    get :create_branch, params: {
      project_id: @project,
      issue_id: issue.id,
      repository_id: repo.id,
      prefix: 'hotfix'
    }

    assert_response :redirect
    assert_match %r{github\.com/redmine/redmine_dev_integration/tree/hotfix/}, response.location
  end

  def test_create_branch_uses_issue_id_when_no_issue_key
    issue = Issue.generate!(project: @project, subject: 'Test')
    repo = ExternalRepository.create!(valid_attributes.merge(redmine_project: @project))

    get :create_branch, params: {project_id: @project, issue_id: issue.id, repository_id: repo.id}

    assert_response :redirect
    assert_match %r{/tree/feature/}, response.location
  end

  def test_create_branch_redirects_to_gitlab
    issue = Issue.generate!(project: @project, subject: 'Fix login bug')
    repo = ExternalRepository.create!(
      valid_attributes.merge(
        redmine_project: @project,
        provider: 'gitlab',
        provider_repository_id: '456',
        url: 'https://gitlab.example.com/redmine/repo'
      )
    )

    get :create_branch, params: {project_id: @project, issue_id: issue.id, repository_id: repo.id}

    assert_response :redirect
    assert_match %r{gitlab\.example\.com/redmine/repo/-/tree/feature/}, response.location
  end

  def test_create_branch_redirects_to_bitbucket
    issue = Issue.generate!(project: @project, subject: 'Fix login bug')
    repo = ExternalRepository.create!(
      valid_attributes.merge(
        redmine_project: @project,
        provider: 'bitbucket',
        provider_repository_id: '550e8400-e29b-41d4-a716-446655440000',
        url: 'https://bitbucket.org/team/repo'
      )
    )

    get :create_branch, params: {project_id: @project, issue_id: issue.id, repository_id: repo.id}

    assert_response :redirect
    assert_match %r{bitbucket\.org/team/repo/src/feature/}, response.location
  end

  def test_create_branch_denied_without_view_permission
    @request.session[:user_id] = 3
    issue = Issue.generate!(project: @project, subject: 'Test')
    repo = ExternalRepository.create!(valid_attributes.merge(redmine_project: @project))

    get :create_branch, params: {project_id: @project, issue_id: issue.id, repository_id: repo.id}

    assert_response :forbidden
  end

  def test_create_branch_rejects_inactive_repository
    issue = Issue.generate!(project: @project, subject: 'Test')
    repo = ExternalRepository.create!(valid_attributes.merge(redmine_project: @project, active: false))

    assert_raises(ActiveRecord::RecordNotFound) do
      get :create_branch, params: {project_id: @project, issue_id: issue.id, repository_id: repo.id}
    end
  end

  def test_mark_deployment_failed
    repository = ExternalRepository.create!(valid_attributes.merge(redmine_project: @project))
    deployment = ExternalDeployment.create!(
      provider: 'github',
      external_repository: repository,
      provider_deployment_id: 'deploy-mark-fail',
      environment_name: 'production',
      status: 'success',
      sha: 'abc123'
    )

    post :mark_deployment_failed, params: {project_id: @project.identifier, deployment_id: deployment.id}

    assert_redirected_to project_deployment_overview_path(@project)
    assert_equal 'failed', deployment.reload.status
    assert_equal 'Successful update.', flash[:notice]
  end

  def test_mark_deployment_failed_scoped_to_project
    other_project = projects(:projects_002)
    other_repo = ExternalRepository.create!(
      provider: 'github',
      provider_repository_id: '999',
      owner: 'other',
      repo_name: 'other-project',
      full_name: 'other/other-project',
      url: 'https://github.com/other/other-project',
      redmine_project: other_project,
      active: true
    )
    deployment = ExternalDeployment.create!(
      provider: 'github',
      external_repository: other_repo,
      provider_deployment_id: 'deploy-other',
      environment_name: 'production',
      status: 'success',
      sha: 'abc123'
    )

    assert_raises(ActiveRecord::RecordNotFound) do
      post :mark_deployment_failed, params: {project_id: @project.identifier, deployment_id: deployment.id}
    end

    assert_equal 'success', deployment.reload.status
  end

  private

  def valid_attributes
    {
      provider: 'github',
      provider_repository_id: '123',
      owner: 'redmine',
      repo_name: 'redmine_dev_integration',
      full_name: 'redmine/redmine_dev_integration',
      url: 'https://github.com/redmine/redmine_dev_integration',
      redmine_repository_id: repositories(:repositories_001).id,
      active: true
    }
  end

  def stub_github_enabled
    Setting.stubs(:plugin_redmine_dev_integration).returns({'github_provider_enabled' => '1'})
  end

  def stub_github_disabled
    Setting.stubs(:plugin_redmine_dev_integration).returns({'github_provider_enabled' => '0'})
  end

  def capture_repository_audits
    audit_calls = []
    audit_service = Object.new
    audit_service.define_singleton_method(:call) do |**kwargs|
      audit_calls << kwargs
      nil
    end

    RedmineDevIntegration::RepositoryAuditService.stubs(:new).returns(audit_service)
    yield audit_calls
  end
end
