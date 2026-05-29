require 'pathname'

Redmine::Plugin.register :redmine_dev_integration do
  name 'Redmine Dev Integration'
  author 'tnowad'
  author_url 'https://github.com/tnowad/redmine_dev_integration'
  url 'https://github.com/tnowad/redmine_dev_integration'
  description 'Development integration plugin skeleton'
  version '0.1.0'
  requires_redmine version_or_higher: '6.0.0'
  settings default: {
    'github_webhook_secret' => '',
    'github_provider_enabled' => '1',
    'github_api_token' => '',
    'github_oauth_client_id' => '',
    'github_oauth_client_secret' => '',
    'github_oauth_access_token' => '',
    'github_oauth_refresh_token' => '',
    'github_oauth_connected_at' => '',
    'github_oauth_token_expires_at' => '',
    'gitlab_webhook_token' => '',
    'gitlab_provider_enabled' => '1',
    'gitlab_api_token' => '',
    'gitlab_base_url' => '',
    'gitlab_oauth_app_id' => '',
    'gitlab_oauth_app_secret' => '',
    'gitlab_oauth_access_token' => '',
    'gitlab_oauth_refresh_token' => '',
    'gitlab_oauth_connected_at' => '',
    'gitlab_oauth_token_expires_at' => '',
    'bitbucket_webhook_secret' => '',
    'bitbucket_provider_enabled' => '1',
    'bitbucket_api_token' => '',
    'bitbucket_oauth_key' => '',
    'bitbucket_oauth_secret' => '',
    'bitbucket_oauth_access_token' => '',
    'bitbucket_oauth_refresh_token' => '',
    'bitbucket_oauth_connected_at' => '',
    'bitbucket_oauth_token_expires_at' => ''
  }, partial: 'settings/redmine_dev_integration'

  menu :project_menu, :dora_metrics,
       { controller: 'projects/dora_metrics', action: 'show' },
       param: :project_id,
       caption: :label_dora_metrics,
       after: :activity,
       permission: :view_development_integration

  project_module :redmine_dev_integration do
    permission :view_development_integration, {}, require: :member
    permission :manage_development_integration, {}, require: :member
    permission :manage_provider_webhooks, {}, require: :member
    permission :trigger_provider_sync, {}, require: :member
  end
end

plugin_root = Pathname.new(__dir__)

require_relative 'lib/redmine_dev_integration/encrypted_setting'
require_relative 'lib/redmine_dev_integration/oauth/token_store'
require_relative 'lib/redmine_dev_integration/oauth_state_store'
require_relative 'lib/redmine_dev_integration/issue_key_extractor'
require_relative 'lib/redmine_dev_integration/github_webhook_signature_verifier'
require_relative 'lib/redmine_dev_integration/gitlab_webhook_token_verifier'
require_relative 'lib/redmine_dev_integration/bitbucket_webhook_signature_verifier'
require_relative 'lib/redmine_dev_integration/provider_event_logger'
require_relative 'lib/redmine_dev_integration/external_repository_resolver'
require_relative 'lib/redmine_dev_integration/external_provider_event_processor'
require_relative 'lib/redmine_dev_integration/provider_repository_parser'
require_relative 'lib/redmine_dev_integration/provider_repository_validator'
require_relative 'lib/redmine_dev_integration/audit_note_service'
require_relative 'lib/redmine_dev_integration/repository_audit_service'
require_relative 'lib/redmine_dev_integration/automation_service'
require_relative 'lib/redmine_dev_integration/sha_issue_tracer'
require_relative 'lib/redmine_dev_integration/reconciliation_service'
require_relative 'lib/redmine_dev_integration/provider_clients/bitbucket_client'
require_relative 'lib/redmine_dev_integration/provider_user_resolver'
require_relative 'lib/redmine_dev_integration/github_push_branch_processor'
require_relative 'lib/redmine_dev_integration/github_pull_request_processor'
require_relative 'lib/redmine_dev_integration/gitlab_push_branch_processor'
require_relative 'lib/redmine_dev_integration/gitlab_merge_request_processor'
require_relative 'lib/redmine_dev_integration/bitbucket_push_branch_processor'
require_relative 'lib/redmine_dev_integration/bitbucket_pull_request_processor'
require_relative 'lib/redmine_dev_integration/issue_linker'
require_relative 'lib/redmine_dev_integration/issue_development_panel_data'
require_relative 'lib/redmine_dev_integration/development_panel_visibility'
require_relative 'lib/redmine_dev_integration/project_patch'
require_relative 'lib/redmine_dev_integration/metrics_service'
require_relative 'lib/redmine_dev_integration/setting_patch'
require_relative 'lib/redmine_dev_integration/projects_helper_patch'
require_relative 'lib/redmine_dev_integration/issues_helper_patch'
require_relative 'lib/redmine_dev_integration/issues_controller_patch'
require_relative 'lib/redmine_dev_integration/changeset_issue_key_linker'
require_relative 'lib/redmine_dev_integration/webhook_registration_service'
require_relative 'lib/redmine_dev_integration/changeset_patch'
require_relative 'lib/redmine_dev_integration/smart_commit_parser'
require_relative 'lib/redmine_dev_integration/smart_commit_service'
require_relative 'lib/redmine_dev_integration/deployment_overview_service'
require_relative 'lib/redmine_dev_integration/github_pull_request_review_processor'
require_relative 'lib/redmine_dev_integration/github_workflow_run_processor'
require_relative 'lib/redmine_dev_integration/github_deployment_status_processor'
require_relative 'lib/redmine_dev_integration/github_release_processor'
require_relative 'lib/redmine_dev_integration/gitlab_pipeline_processor'
require_relative 'lib/redmine_dev_integration/gitlab_deployment_processor'
require_relative 'lib/redmine_dev_integration/gitlab_release_processor'
require_relative 'lib/redmine_dev_integration/bitbucket_pipeline_processor'
require_relative 'lib/redmine_dev_integration/bitbucket_deployment_processor'
require_relative 'lib/redmine_dev_integration/scheduled_reconciliation_runner'
require_relative 'lib/redmine_dev_integration/oauth/github_authorization_service'
require_relative 'lib/redmine_dev_integration/oauth/gitlab_authorization_service'
require_relative 'lib/redmine_dev_integration/oauth/bitbucket_authorization_service'
require_relative 'lib/redmine_dev_integration/dev_integration_hook_listener'
require_relative 'app/models/dev_integration_mailer'

apply_redmine_dev_integration_patches = lambda do
  ProjectsHelper.prepend RedmineDevIntegration::ProjectsHelperPatch unless ProjectsHelper < RedmineDevIntegration::ProjectsHelperPatch
  IssuesHelper.prepend RedmineDevIntegration::IssuesHelperPatch unless IssuesHelper < RedmineDevIntegration::IssuesHelperPatch
  IssuesController.prepend RedmineDevIntegration::IssuesControllerPatch unless IssuesController < RedmineDevIntegration::IssuesControllerPatch
  Project.include RedmineDevIntegration::ProjectPatch
  Setting.singleton_class.prepend RedmineDevIntegration::SettingPatch unless Setting.singleton_class < RedmineDevIntegration::SettingPatch
  Changeset.include RedmineDevIntegration::ChangesetPatch unless Changeset < RedmineDevIntegration::ChangesetPatch
end

if Rails.application.reloader.respond_to?(:to_prepare)
  Rails.application.reloader.to_prepare(&apply_redmine_dev_integration_patches)
else
  ActiveSupport::Reloader.to_prepare(&apply_redmine_dev_integration_patches)
end

apply_redmine_dev_integration_patches.call

Rails.application.config.after_initialize do
  next unless defined?(RedmineDevIntegration::ScheduledReconciliationRunner)

  ActiveSupport::Notifications.subscribe('process_action.action_controller') do
    # Per-request overhead: one Time.current comparison (~nanoseconds).
    # The 15-min guard prevents the SETNX below from firing more than
    # once every 15 minutes per process; SETNX itself is O(1) in Redis.
    @recon_last_check ||= Time.at(0)
    next if Time.current - @recon_last_check < 15.minutes
    @recon_last_check = Time.current

    lock_key = 'redmine_dev_integration:auto_reconcile_lock'
    next unless Rails.cache.write(lock_key, true, expires_in: 30.seconds, unless_exist: true)

    begin
      ReconciliationJob.perform_later
    rescue StandardError => e
      Rails.logger.warn "[DevIntegration] Auto-reconciliation enqueue failed: #{e.message}"
    ensure
      Rails.cache.delete(lock_key)
    end
  end
end

load plugin_root.join('config/routes.rb')

unless Rails.application.routes.named_routes.key?(:dev_mark_deployment_failed)
  Rails.application.routes.append do
    resources :projects, only: [] do
      post 'deployments/:deployment_id/mark_failed', to: 'projects/redmine_dev_integration#mark_deployment_failed', as: :dev_mark_deployment_failed
    end
  end
end

unless Rails.application.routes.named_routes.key?(:create_branch_dev_integration)
  Rails.application.routes.append do
    get '/projects/:project_id/issues/:issue_id/dev_integration/create_branch',
        to: 'projects/redmine_dev_integration#create_branch',
        as: :create_branch_dev_integration
  end
end
