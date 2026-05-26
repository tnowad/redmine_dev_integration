# frozen_string_literal: true

require_relative '../test_helper'

class OauthFlowTest < Redmine::IntegrationTest
  setup do
    Setting.stubs(:plugin_redmine_dev_integration).returns({
      'github_oauth_client_id' => 'test_client_id',
      'github_oauth_client_secret' => 'encrypted_test_secret',
      'github_provider_enabled' => '1',
      'gitlab_oauth_app_id' => 'test_app_id',
      'gitlab_oauth_app_secret' => 'encrypted_test_secret',
      'gitlab_base_url' => 'https://gitlab.example.com',
      'gitlab_provider_enabled' => '1'
    })
    Setting.stubs(:protocol).returns('https')
    Setting.stubs(:host_name).returns('redmine.example.com')
    RedmineDevIntegration::EncryptedSetting.stubs(:decrypt).returns('test_secret')
    RedmineDevIntegration::EncryptedSetting.stubs(:encrypt).returns('encrypted_test_value')
  end

  def oauth_state_from_redirect(location)
    return nil unless location
    params = URI.parse(location).query
    return nil unless params
    URI.decode_www_form(params).to_h['state']
  end

  def test_github_oauth_start_redirects_to_github_authorize_with_correct_params
    log_user('admin', 'admin')
    get '/dev_integrations/github/oauth/start'
    assert_response :redirect
    assert_match %r{https://github.com/login/oauth/authorize}, response.location
    assert_match /client_id=test_client_id/, response.location
    assert_match /redirect_uri=/, response.location
    assert_match /scope=repo/, response.location
    state = oauth_state_from_redirect(response.location)
    assert_not_nil state, 'OAuth state should be present in redirect URL'
  end

  def test_github_oauth_callback_exchanges_code_and_stores_tokens_via_token_store
    log_user('admin', 'admin')

    mock_response = mock('http_response')
    mock_response.stubs(:is_a?).with(Net::HTTPSuccess).returns(true)
    mock_response.stubs(:body).returns(
      {
        access_token: 'gho_test_token',
        refresh_token: 'ghr_test_refresh',
        expires_in: 28800
      }.to_json
    )
    mock_response.stubs(:code).returns('200')
    Net::HTTP.stubs(:post_form).returns(mock_response)

    get '/dev_integrations/github/oauth/start'
    state = oauth_state_from_redirect(response.location)
    assert_not_nil state

    get "/dev_integrations/github/oauth/callback?code=test_code&state=#{state}"
    assert_redirected_to '/settings/plugin/redmine_dev_integration'
    assert_equal 'Successfully connected Github OAuth.', flash[:notice]
  end

  def test_callback_state_mismatch_redirects_with_alert_message
    log_user('admin', 'admin')

    get '/dev_integrations/github/oauth/callback?code=test_code&state=invalid_state'
    assert_redirected_to '/settings/plugin/redmine_dev_integration'
    assert_equal 'Invalid OAuth state.', flash[:alert]
  end

  def test_disconnect_clears_github_oauth_tokens
    log_user('admin', 'admin')

    Setting.expects(:plugin_redmine_dev_integration=).with do |hash|
      hash['github_oauth_access_token'] == '' &&
        hash['github_oauth_refresh_token'] == '' &&
        hash['github_oauth_connected_at'].nil?
    end

    post '/dev_integrations/github/oauth/disconnect'
    assert_redirected_to '/settings/plugin/redmine_dev_integration'
  end

  def test_disconnect_clears_gitlab_oauth_tokens
    log_user('admin', 'admin')

    Setting.expects(:plugin_redmine_dev_integration=).with do |hash|
      hash['gitlab_oauth_access_token'] == '' &&
        hash['gitlab_oauth_refresh_token'] == '' &&
        hash['gitlab_oauth_connected_at'].nil?
    end

    post '/dev_integrations/gitlab/oauth/disconnect'
    assert_redirected_to '/settings/plugin/redmine_dev_integration'
  end

  def test_gitlab_oauth_start_redirects_with_custom_base_url
    log_user('admin', 'admin')

    get '/dev_integrations/gitlab/oauth/start'
    assert_response :redirect
    assert_match %r{https://gitlab.example.com/oauth/authorize}, response.location
    assert_match /client_id=test_app_id/, response.location
  end

  def test_non_admin_user_cannot_access_github_oauth_start
    log_user('jsmith', 'jsmith')

    get '/dev_integrations/github/oauth/start'
    assert_response :forbidden
  end

  def test_non_admin_user_cannot_access_gitlab_oauth_start
    log_user('jsmith', 'jsmith')

    get '/dev_integrations/gitlab/oauth/start'
    assert_response :forbidden
  end

  def test_non_admin_user_cannot_disconnect
    log_user('jsmith', 'jsmith')

    post '/dev_integrations/github/oauth/disconnect'
    assert_response :forbidden
  end

  def test_invalid_provider_start_returns_not_found
    log_user('admin', 'admin')

    get '/dev_integrations/invalid_provider/oauth/start'
    assert_response :not_found
  end

  def test_callback_handles_token_exchange_http_error
    log_user('admin', 'admin')

    mock_response = mock('http_error_response')
    mock_response.stubs(:is_a?).with(Net::HTTPSuccess).returns(false)
    mock_response.stubs(:code).returns('400')
    Net::HTTP.stubs(:post_form).returns(mock_response)

    get '/dev_integrations/github/oauth/start'
    state = oauth_state_from_redirect(response.location)

    get "/dev_integrations/github/oauth/callback?code=test_code&state=#{state}"
    assert_redirected_to '/settings/plugin/redmine_dev_integration'
    assert_match /OAuth error/, flash[:alert]
  end

  def test_callback_rejects_missing_authorization_code
    log_user('admin', 'admin')

    get '/dev_integrations/github/oauth/start'
    state = oauth_state_from_redirect(response.location)

    get "/dev_integrations/github/oauth/callback?state=#{state}"
    assert_redirected_to '/settings/plugin/redmine_dev_integration'
    assert_equal 'Authorization code missing.', flash[:alert]
  end
end
