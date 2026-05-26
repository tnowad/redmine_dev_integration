# frozen_string_literal: true

require_relative '../test_helper'

class RedmineDevIntegrationSettingsPartialTest < ActionView::TestCase
  def test_settings_partial_renders_secret_and_provider_controls
    settings = {
      'github_webhook_secret' => 'topsecret',
      'github_provider_enabled' => '1',
      'github_api_token' => 'github-api-token',
      'gitlab_webhook_token' => 'topsecret-2',
      'gitlab_provider_enabled' => '0',
      'gitlab_api_token' => 'gitlab-api-token'
    }

    render partial: 'settings/redmine_dev_integration', locals: {settings: settings}

    assert_select 'input[type=password][name=?]', 'settings[github_webhook_secret]'
    assert_select 'input[type=password][name=?][placeholder=?]', 'settings[github_webhook_secret]', 'Leave blank to keep current value'
    assert_no_match(/topsecret/, rendered)
    assert_select 'input[type=checkbox][name=?][checked=checked]', 'settings[github_provider_enabled]'
    assert_select 'input[type=hidden][name=?][value=?]', 'settings[github_provider_enabled]', '0'
    assert_select 'input[type=password][name=?]', 'settings[github_api_token]'
    assert_select 'input[type=password][name=?][placeholder=?]', 'settings[github_api_token]', 'Leave blank to keep current value'
    assert_no_match(/github-api-token/, rendered)
    assert_select 'input[type=password][name=?]', 'settings[gitlab_webhook_token]'
    assert_select 'input[type=password][name=?][placeholder=?]', 'settings[gitlab_webhook_token]', 'Leave blank to keep current value'
    assert_no_match(/topsecret-2/, rendered)
    assert_select 'input[type=checkbox][name=?][checked=checked]', 'settings[gitlab_provider_enabled]', false
    assert_select 'input[type=hidden][name=?][value=?]', 'settings[gitlab_provider_enabled]', '0'
    assert_select 'input[type=password][name=?]', 'settings[gitlab_api_token]'
    assert_select 'input[type=password][name=?][placeholder=?]', 'settings[gitlab_api_token]', 'Leave blank to keep current value'
    assert_no_match(/gitlab-api-token/, rendered)
    assert_select 'em.info', text: 'configured', count: 4
  end
end
