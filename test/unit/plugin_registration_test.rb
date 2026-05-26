# frozen_string_literal: true

require_relative '../test_helper'

class PluginRegistrationTest < ActiveSupport::TestCase
  def test_plugin_registers_permissions
    plugin = Redmine::Plugin.find(:redmine_dev_integration)
    permissions =
      Redmine::AccessControl.permissions.
        select {|permission| permission.project_module == :redmine_dev_integration}.
        map(&:name)

    assert_equal 'Redmine Dev Integration', plugin.name
    assert_equal %i[
      view_development_integration
      manage_development_integration
      manage_provider_webhooks
      trigger_provider_sync
    ], permissions
  end

  def test_plugin_registers_settings_defaults
    plugin = Redmine::Plugin.find(:redmine_dev_integration)

    assert_equal 'settings/redmine_dev_integration', plugin.settings[:partial]
    assert_equal({
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
    }, plugin.settings[:default])
  end

  def test_routes_file_is_idempotent_when_loaded_twice
    routes = Rails.application.routes.routes
    initial_count = routes.count {|route| route.path.spec.to_s == '/dev_integrations/github/webhook'}
    initial_gitlab_count = routes.count {|route| route.path.spec.to_s == '/dev_integrations/gitlab/webhook'}

    load Rails.root.join('plugins/redmine_dev_integration/config/routes.rb')

    reloaded_count = Rails.application.routes.routes.count {|route| route.path.spec.to_s == '/dev_integrations/github/webhook'}
    reloaded_gitlab_count = Rails.application.routes.routes.count {|route| route.path.spec.to_s == '/dev_integrations/gitlab/webhook'}

    assert_equal initial_count, reloaded_count
    assert_equal initial_gitlab_count, reloaded_gitlab_count
  end
end
