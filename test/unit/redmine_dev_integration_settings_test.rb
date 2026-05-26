# frozen_string_literal: true

require_relative '../test_helper'

class RedmineDevIntegrationSettingsTest < ActiveSupport::TestCase
  def test_blank_secret_submission_preserves_existing_secret_and_updates_other_values
    Setting.stubs(:plugin_redmine_dev_integration).returns({
      'github_webhook_secret' => 'initial-secret',
      'github_provider_enabled' => '1',
      'github_api_token' => 'initial-github-api-token',
      'gitlab_webhook_token' => 'initial-token',
      'gitlab_provider_enabled' => '1',
      'gitlab_api_token' => 'initial-gitlab-api-token'
    })

    Setting.expects(:[]=).with(:plugin_redmine_dev_integration, {
      'github_webhook_secret' => 'initial-secret',
      'github_provider_enabled' => '0',
      'github_api_token' => 'initial-github-api-token',
      'gitlab_webhook_token' => 'initial-token',
      'gitlab_provider_enabled' => '0',
      'gitlab_api_token' => 'initial-gitlab-api-token'
    })

    Setting.plugin_redmine_dev_integration = {
      'github_webhook_secret' => '',
      'github_provider_enabled' => '0',
      'github_api_token' => '',
      'gitlab_webhook_token' => '',
      'gitlab_provider_enabled' => '0',
      'gitlab_api_token' => ''
    }

    Setting.stubs(:plugin_redmine_dev_integration).returns({
      'github_webhook_secret' => 'initial-secret',
      'github_provider_enabled' => '0',
      'github_api_token' => 'initial-github-api-token',
      'gitlab_webhook_token' => 'initial-token',
      'gitlab_provider_enabled' => '0',
      'gitlab_api_token' => 'initial-gitlab-api-token'
    })

    Setting.expects(:[]=).with(:plugin_redmine_dev_integration, {
      'github_webhook_secret' => 'new-secret',
      'github_provider_enabled' => '0',
      'github_api_token' => 'new-github-api-token',
      'gitlab_webhook_token' => 'new-token',
      'gitlab_provider_enabled' => '0',
      'gitlab_api_token' => 'new-gitlab-api-token'
    })

    Setting.plugin_redmine_dev_integration = {
      'github_webhook_secret' => 'new-secret',
      'github_provider_enabled' => '0',
      'github_api_token' => 'new-github-api-token',
      'gitlab_webhook_token' => 'new-token',
      'gitlab_provider_enabled' => '0',
      'gitlab_api_token' => 'new-gitlab-api-token'
    }
  end

  def test_encrypted_setting_preserves_existing_on_blank_submission
    encrypted = RedmineDevIntegration::EncryptedSetting.encrypt('preserved-secret')
    existing = { 'github_oauth_client_secret' => encrypted }
    Setting.stubs(:plugin_redmine_dev_integration).returns(existing)

    settings = { 'github_oauth_client_secret' => '' }

    patch = Setting.singleton_class.ancestors.find { |m| m.name == 'RedmineDevIntegration::SettingPatch' }
    patch.instance_method(:encrypted_setting!).bind_call(Setting, settings, 'github_oauth_client_secret')

    assert_equal encrypted, settings['github_oauth_client_secret']
    assert_equal 'preserved-secret', RedmineDevIntegration::EncryptedSetting.decrypt(settings['github_oauth_client_secret'])
  end

  def test_encrypted_setting_encrypts_new_value
    Setting.stubs(:plugin_redmine_dev_integration).returns({})

    settings = { 'github_oauth_client_secret' => 'new-secret-value' }

    patch = Setting.singleton_class.ancestors.find { |m| m.name == 'RedmineDevIntegration::SettingPatch' }
    patch.instance_method(:encrypted_setting!).bind_call(Setting, settings, 'github_oauth_client_secret')

    refute_equal 'new-secret-value', settings['github_oauth_client_secret']
    assert_equal 'new-secret-value', RedmineDevIntegration::EncryptedSetting.decrypt(settings['github_oauth_client_secret'])
  end
end
