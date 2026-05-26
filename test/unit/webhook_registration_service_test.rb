# frozen_string_literal: true

require_relative '../test_helper'

class WebhookRegistrationServiceTest < ActiveSupport::TestCase
  fixtures :projects, :repositories

  def setup
    @service = RedmineDevIntegration::WebhookRegistrationService.new
    setup_github_settings
    setup_gitlab_settings
    @github_repository = build_github_repository
    @gitlab_repository = build_gitlab_repository
    @webhook_url = 'https://redmine.example.com/dev_integrations/github/webhook'
  end

  def test_github_registration_uses_oauth_token_when_available
    client = mock('GitHubClient')
    client.stubs(:credentials_missing?).returns(false)
    client.expects(:list_webhooks).with(repository: @github_repository).returns([])
    client.expects(:create_webhook).returns('id' => 12345)

    RedmineDevIntegration::ProviderClients::GitHubClient.stubs(:new).returns(client)

    result = @service.register(repository: @github_repository, redmine_webhook_url: @webhook_url)

    assert_predicate result, :success?
    assert_equal 'Webhook created', result.message
  end

  def test_gitlab_registration_uses_oauth_token_when_available
    client = mock('GitLabClient')
    client.stubs(:credentials_missing?).returns(false)
    client.expects(:list_webhooks).with(repository: @gitlab_repository).returns([])
    client.expects(:create_webhook).returns('id' => 678)

    RedmineDevIntegration::ProviderClients::GitLabClient.stubs(:new).returns(client)

    result = @service.register(repository: @gitlab_repository, redmine_webhook_url: @webhook_url)

    assert_predicate result, :success?
    assert_equal 'Webhook created', result.message
  end

  def test_github_webhook_registration_creates_new_hook
    client = mock_github_client
    client.expects(:list_webhooks).with(repository: @github_repository).returns([])
    client.expects(:create_webhook).with(
      repository: @github_repository,
      url: @webhook_url,
      secret: 'test-secret'
    ).returns('id' => 12345, 'url' => @webhook_url)

    RedmineDevIntegration::ProviderClients::GitHubClient.stubs(:new).returns(client)

    result = @service.register(repository: @github_repository, redmine_webhook_url: @webhook_url)

    assert_predicate result, :success?
    assert_equal 'Webhook created', result.message
    assert_equal '12345', @github_repository.reload.provider_webhook_id
    assert_equal 'registered', @github_repository.reload.webhook_registration_status
    assert_not_nil @github_repository.reload.webhook_registered_at
  end

  def test_github_webhook_registration_updates_existing_hook
    existing = [{'id' => 12345, 'config' => {'url' => @webhook_url}}]

    client = mock_github_client
    client.expects(:list_webhooks).with(repository: @github_repository).returns(existing)
    client.expects(:update_webhook).with(
      repository: @github_repository,
      webhook_id: 12345,
      url: @webhook_url,
      secret: 'test-secret'
    ).returns('id' => 12345)

    RedmineDevIntegration::ProviderClients::GitHubClient.stubs(:new).returns(client)

    result = @service.register(repository: @github_repository, redmine_webhook_url: @webhook_url)

    assert_predicate result, :success?
    assert_equal 'Webhook updated', result.message
    assert_equal '12345', @github_repository.reload.provider_webhook_id
    assert_equal 'registered', @github_repository.reload.webhook_registration_status
  end

  def test_github_registration_fails_when_secret_missing
    Setting.stubs(:plugin_redmine_dev_integration).returns('github_webhook_secret' => '')

    result = @service.register(repository: @github_repository, redmine_webhook_url: @webhook_url)

    assert_predicate result, :error?
    assert_equal 'GitHub webhook secret is not configured', result.message
  end

  def test_github_registration_fails_when_api_fails
    client = mock_github_client
    client.expects(:list_webhooks).with(repository: @github_repository).returns([])
    client.expects(:create_webhook).raises(StandardError.new('API failure'))

    RedmineDevIntegration::ProviderClients::GitHubClient.stubs(:new).returns(client)

    result = @service.register(repository: @github_repository, redmine_webhook_url: @webhook_url)

    assert_predicate result, :error?
    assert_equal 'API failure', result.message
    assert_equal 'error', @github_repository.reload.webhook_registration_status
  end

  def test_gitlab_webhook_registration_creates_new_hook
    client = mock_gitlab_client
    client.expects(:list_webhooks).with(repository: @gitlab_repository).returns([])
    client.expects(:create_webhook).with(
      repository: @gitlab_repository,
      url: @webhook_url,
      token: 'test-token'
    ).returns('id' => 678)

    RedmineDevIntegration::ProviderClients::GitLabClient.stubs(:new).returns(client)

    result = @service.register(repository: @gitlab_repository, redmine_webhook_url: @webhook_url)

    assert_predicate result, :success?
    assert_equal 'Webhook created', result.message
    assert_equal '678', @gitlab_repository.reload.provider_webhook_id
    assert_equal 'registered', @gitlab_repository.reload.webhook_registration_status
  end

  def test_gitlab_registration_fails_when_token_missing
    Setting.stubs(:plugin_redmine_dev_integration).returns(
      'gitlab_webhook_token' => '',
      'gitlab_api_token' => 'token'
    )

    result = @service.register(repository: @gitlab_repository, redmine_webhook_url: @webhook_url)

    assert_predicate result, :error?
    assert_equal 'GitLab webhook secret token is not configured', result.message
  end

  def test_unregistered_webhook_method
    @github_repository.update!(webhook_registration_status: 'not_registered')
    assert_not_predicate @github_repository, :webhook_registered?

    @github_repository.update!(webhook_registration_status: 'registered')
    assert_predicate @github_repository, :webhook_registered?

    @github_repository.update!(webhook_registration_status: 'error')
    assert_not_predicate @github_repository, :webhook_registered?
  end

  def test_unsupported_provider_returns_error
    repo = ExternalRepository.new(
      provider: 'bitbucket',
      provider_repository_id: '1',
      owner: 'test',
      repo_name: 'test',
      full_name: 'test/test',
      url: 'https://bitbucket.org/test/test',
      redmine_project: projects(:projects_001),
      active: true
    )

    result = @service.register(repository: repo, redmine_webhook_url: @webhook_url)
    assert_predicate result, :error?
    assert_includes result.message, 'Unsupported provider'
  end

  private

  def setup_github_settings
    Setting.stubs(:plugin_redmine_dev_integration).returns(
      'github_webhook_secret' => 'test-secret',
      'github_api_token' => 'gh-token',
      'gitlab_webhook_token' => 'test-token',
      'gitlab_api_token' => 'gl-token'
    )
  end

  def setup_gitlab_settings
    # Settings already set in setup_github_settings
  end

  def mock_github_client
    mock = mock('GitHubClient')
    mock.stubs(:credentials_missing?).returns(false)
    mock
  end

  def mock_gitlab_client
    mock = mock('GitLabClient')
    mock.stubs(:credentials_missing?).returns(false)
    mock
  end

  def build_github_repository
    ExternalRepository.create!(
      provider: 'github',
      provider_repository_id: '123',
      owner: 'redmine',
      repo_name: 'redmine_dev_integration',
      full_name: 'redmine/redmine_dev_integration',
      url: 'https://github.com/redmine/redmine_dev_integration',
      redmine_project: projects(:projects_001),
      redmine_repository: repositories(:repositories_001),
      active: true
    )
  end

  def build_gitlab_repository
    ExternalRepository.create!(
      provider: 'gitlab',
      provider_repository_id: '456',
      owner: 'redmine/subgroup',
      repo_name: 'redmine_dev_integration',
      full_name: 'redmine/subgroup/redmine_dev_integration',
      url: 'https://gitlab.example.com/redmine/subgroup/redmine_dev_integration',
      redmine_project: projects(:projects_001),
      active: true
    )
  end
end
