require 'pathname'

Redmine::Plugin.register :redmine_dev_integration do
  name 'Redmine Dev Integration'
  author 'Redmine Dev Integration'
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
require_relative 'lib/redmine_dev_integration/oauth_state_store'
require_relative 'lib/redmine_dev_integration/oauth/token_store'
require_relative 'lib/redmine_dev_integration/oauth/github_authorization_service'
require_relative 'lib/redmine_dev_integration/oauth/gitlab_authorization_service'
require_relative 'lib/redmine_dev_integration/oauth/bitbucket_authorization_service'

apply_redmine_dev_integration_patches = lambda do
  ProjectsHelper.prepend RedmineDevIntegration::ProjectsHelperPatch unless ProjectsHelper < RedmineDevIntegration::ProjectsHelperPatch
  IssuesHelper.prepend RedmineDevIntegration::IssuesHelperPatch unless IssuesHelper < RedmineDevIntegration::IssuesHelperPatch
  IssuesController.prepend RedmineDevIntegration::IssuesControllerPatch unless IssuesController < RedmineDevIntegration::IssuesControllerPatch
  Project.include RedmineDevIntegration::ProjectPatch unless Project < RedmineDevIntegration::ProjectPatch
  Setting.singleton_class.prepend RedmineDevIntegration::SettingPatch unless Setting.singleton_class < RedmineDevIntegration::SettingPatch
  Changeset.include RedmineDevIntegration::ChangesetPatch unless Changeset < RedmineDevIntegration::ChangesetPatch
end

if Rails.application.reloader.respond_to?(:to_prepare)
  Rails.application.reloader.to_prepare(&apply_redmine_dev_integration_patches)
else
  ActiveSupport::Reloader.to_prepare(&apply_redmine_dev_integration_patches)
end

apply_redmine_dev_integration_patches.call

# Auto-reconciliation: checks once every 15 minutes if any active repositories
# are due for reconciliation, triggered by the next incoming request.
reconciliation_scheduler = lambda do
  lock_key = 'redmine_dev_integration:auto_reconcile_lock'
  last_run_key = 'redmine_dev_integration:auto_reconcile_last_run'

  last_run = Rails.cache.read(last_run_key)
  return if last_run && last_run > 15.minutes.ago

  return unless Rails.cache.write(lock_key, true, expires_in: 30.seconds, unless_exist: true)

  begin
    Rails.cache.write(last_run_key, Time.current, expires_in: 1.hour)
    runner = RedmineDevIntegration::ScheduledReconciliationRunner.new
    runner.call
  rescue StandardError => e
    Rails.logger.warn "[DevIntegration] Auto-reconciliation failed: #{e.message}"
  ensure
    Rails.cache.delete(lock_key)
  end
end

Rails.application.config.after_initialize do
  ActiveSupport::Notifications.subscribe('process_action.action_controller') do
    reconciliation_scheduler.call if defined?(RedmineDevIntegration::ScheduledReconciliationRunner)
  end
end

load plugin_root.join('config/routes.rb')
