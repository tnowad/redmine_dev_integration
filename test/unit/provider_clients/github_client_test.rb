# frozen_string_literal: true

require_relative '../../test_helper'

class GithubClientTest < ActiveSupport::TestCase
  def setup
    # Clear settings to avoid OAuth token leakage between tests  
    Setting.where(name: 'plugin_redmine_dev_integration').delete_all
  end

  def teardown
    Setting.where(name: 'plugin_redmine_dev_integration').delete_all
  end

  def test_credentials_are_required
    Setting.plugin_redmine_dev_integration = {}
    client = RedmineDevIntegration::ProviderClients::GitHubClient.new(settings: {})

    assert_predicate client, :credentials_missing?
  end

  def setup_oauth_github_token
    Setting.plugin_redmine_dev_integration = {
      'github_webhook_secret' => '',
      'github_provider_enabled' => '1',
      'github_oauth_access_token' => RedmineDevIntegration::EncryptedSetting.encrypt('oauth-github-token'),
      'github_oauth_connected_at' => Time.current.iso8601
    }
  end

  def test_oauth_token_preferred_over_pat
    setup_oauth_github_token
    Setting.plugin_redmine_dev_integration = (Setting.plugin_redmine_dev_integration || {}).merge('github_api_token' => 'pat-token')

    client = RedmineDevIntegration::ProviderClients::GitHubClient.new

    assert_equal 'oauth-github-token', client.send(:api_token)
    assert_not client.credentials_missing?
  end

  def test_falls_back_to_pat_when_oauth_not_available
    Setting.plugin_redmine_dev_integration = { 'github_api_token' => 'pat-token', 'github_provider_enabled' => '1' }

    client = RedmineDevIntegration::ProviderClients::GitHubClient.new

    assert_equal 'pat-token', client.send(:api_token)
    assert_not client.credentials_missing?
  end

  def test_credentials_missing_with_oauth_returns_false
    setup_oauth_github_token

    client = RedmineDevIntegration::ProviderClients::GitHubClient.new

    assert_not client.credentials_missing?
  end

  def test_recent_pull_requests_normalize_api_payload
    Setting.plugin_redmine_dev_integration = {'github_api_token' => 'token'}
    requests = []
    client = RedmineDevIntegration::ProviderClients::GitHubClient.new(
      settings: {'github_api_token' => 'token'},
      http_getter: lambda do |uri, headers|
        requests << [uri.request_uri, headers]
        JSON.generate([
          {
            'number' => 7,
            'title' => 'Add AUTH-1 support',
            'body' => 'Pull request body',
            'html_url' => 'https://github.com/redmine/redmine_dev_integration/pull/7',
            'state' => 'open',
            'user' => {'login' => 'contributor'},
            'head' => {'ref' => 'feature/AUTH-1'},
            'base' => {'ref' => 'main'},
            'merged' => false,
            'created_at' => '2026-05-25T10:00:00Z',
            'updated_at' => '2026-05-25T10:05:00Z'
          }
        ])
      end
    )
    repository = Struct.new(:full_name).new('redmine/redmine_dev_integration')

    pull_requests = client.recent_pull_requests(repository: repository)

    assert_equal ['/repos/redmine/redmine_dev_integration/pulls?state=all&sort=updated&direction=desc&per_page=100'], requests.map(&:first)
    assert_equal 'Bearer token', requests.first.last['Authorization']
    assert_equal 1, pull_requests.length
    assert_equal 7, pull_requests.first[:number]
    assert_equal 'feature/AUTH-1', pull_requests.first[:source_branch]
    assert_equal Time.zone.parse('2026-05-25T10:05:00Z'), pull_requests.first[:last_event_at]
  end
end
