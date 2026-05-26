# frozen_string_literal: true

require_relative '../../test_helper'

class GitlabClientTest < ActiveSupport::TestCase
  def setup
    Setting.where(name: 'plugin_redmine_dev_integration').delete_all
  end

  def teardown
    Setting.where(name: 'plugin_redmine_dev_integration').delete_all
  end

  def setup_oauth_gitlab_token
    Setting.plugin_redmine_dev_integration = {
      'gitlab_webhook_token' => '',
      'gitlab_provider_enabled' => '1',
      'gitlab_oauth_access_token' => RedmineDevIntegration::EncryptedSetting.encrypt('oauth-gitlab-token'),
      'gitlab_oauth_connected_at' => Time.current.iso8601
    }
  end

  def test_credentials_are_required
    client = RedmineDevIntegration::ProviderClients::GitLabClient.new(settings: {})

    assert_predicate client, :credentials_missing?
  end

  def test_oauth_token_preferred_over_pat
    setup_oauth_gitlab_token
    Setting.plugin_redmine_dev_integration = (Setting.plugin_redmine_dev_integration || {}).merge('gitlab_api_token' => 'pat-token')

    client = RedmineDevIntegration::ProviderClients::GitLabClient.new

    assert_equal 'oauth-gitlab-token', client.send(:api_token)
    assert_not client.credentials_missing?
  end

  def test_oauth_auth_headers_use_bearer
    setup_oauth_gitlab_token
    Setting.plugin_redmine_dev_integration = (Setting.plugin_redmine_dev_integration || {}).merge('gitlab_api_token' => 'pat-token')

    client = RedmineDevIntegration::ProviderClients::GitLabClient.new

    headers = client.send(:auth_headers)
    assert_equal 'Bearer oauth-gitlab-token', headers['Authorization']
    assert_nil headers['PRIVATE-TOKEN']
  end

  def test_pat_auth_headers_use_private_token
    Setting.plugin_redmine_dev_integration = { 'gitlab_api_token' => 'pat-token', 'gitlab_provider_enabled' => '1' }

    client = RedmineDevIntegration::ProviderClients::GitLabClient.new

    headers = client.send(:auth_headers)
    assert_equal 'pat-token', headers['PRIVATE-TOKEN']
    assert_nil headers['Authorization']
  end

  def test_credentials_missing_with_oauth_returns_false
    setup_oauth_gitlab_token

    client = RedmineDevIntegration::ProviderClients::GitLabClient.new

    assert_not client.credentials_missing?
  end

  def test_recent_builds_normalize_api_payload
    Setting.plugin_redmine_dev_integration = {'gitlab_token' => 'token'}
    requests = []
    client = RedmineDevIntegration::ProviderClients::GitLabClient.new(
      settings: {'gitlab_token' => 'token'},
      http_getter: lambda do |uri, headers|
        requests << [uri.request_uri, headers]
        JSON.generate([
          {
            'id' => 101,
            'iid' => 42,
            'name' => 'Pipeline AUTH-1',
            'status' => 'success',
            'web_url' => 'https://gitlab.example.com/redmine/redmine_dev_integration/-/pipelines/101',
            'sha' => 'abc123',
            'ref' => 'main',
            'user' => {'username' => 'contributor'},
            'created_at' => '2026-05-25T10:00:00Z',
            'updated_at' => '2026-05-25T10:05:00Z'
          }
        ])
      end
    )
    repository = Struct.new(:provider_repository_id).new('456')

    builds = client.recent_builds(repository: repository)

    assert_equal ['/api/v4/projects/456/pipelines?order_by=updated_at&sort=desc&per_page=100'], requests.map(&:first)
    assert_equal 'token', requests.first.last['PRIVATE-TOKEN']
    assert_equal 1, builds.length
    assert_equal '101', builds.first[:provider_build_id].to_s
    assert_equal 42, builds.first[:build_number]
    assert_equal 'success', builds.first[:status]
    assert_equal 'main', builds.first[:branch_name]
  end
end
