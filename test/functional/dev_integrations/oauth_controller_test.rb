# frozen_string_literal: true

require_relative '../../test_helper'

class DevIntegrations::OauthControllerTest < Redmine::IntegrationTest
  fixtures :users, :email_addresses, :roles, :member_roles, :members

  def setup
    Setting.stubs(:plugin_redmine_dev_integration).returns({
      'github_oauth_client_id' => 'gh-client-id',
      'github_oauth_client_secret' => RedmineDevIntegration::EncryptedSetting.encrypt('gh-client-secret'),
      'gitlab_oauth_app_id' => 'gl-app-id',
      'gitlab_oauth_app_secret' => RedmineDevIntegration::EncryptedSetting.encrypt('gl-app-secret'),
      'gitlab_base_url' => 'https://gitlab.example.com'
    })
    Setting.stubs(:protocol).returns('https')
    Setting.stubs(:host_name).returns('redmine.example.com')
    @admin = users(:users_001)
  end

  def oauth_state_from_redirect(location)
    return nil unless location
    params = URI.parse(location).query
    return nil unless params
    parsed = URI.decode_www_form(params).to_h
    parsed['state']
  end

  def test_start_redirects_to_github
    log_user('admin', 'admin')
    get '/dev_integrations/github/oauth/start'
    assert_response :redirect
    assert_match %r{https://github.com/login/oauth/authorize}, response.location
    assert_match /client_id=gh-client-id/, response.location
    assert_match /redirect_uri=/, response.location
    assert_match /scope=repo/, response.location
  end

  def test_start_redirects_to_gitlab
    log_user('admin', 'admin')
    get '/dev_integrations/gitlab/oauth/start'
    assert_response :redirect
    assert_match %r{https://gitlab.example.com/oauth/authorize}, response.location
    assert_match /client_id=gl-app-id/, response.location
  end

  def test_start_rejects_non_admin
    log_user('jsmith', 'jsmith')
    get '/dev_integrations/github/oauth/start'
    assert_response :forbidden
  end

  def test_start_rejects_invalid_provider
    log_user('admin', 'admin')
    get '/dev_integrations/invalid_provider/oauth/start'
    assert_response :not_found
  end

  def test_callback_rejects_invalid_state
    log_user('admin', 'admin')
    get '/dev_integrations/github/oauth/callback?code=test-code&state=invalid-state'
    assert_redirected_to '/settings/plugin/redmine_dev_integration'
    assert_equal 'Invalid OAuth state.', flash[:alert]
  end

  def test_callback_rejects_missing_code
    log_user('admin', 'admin')
    get '/dev_integrations/github/oauth/start'
    state = oauth_state_from_redirect(response.location)

    get "/dev_integrations/github/oauth/callback?state=#{state}"
    assert_redirected_to '/settings/plugin/redmine_dev_integration'
    assert_equal 'Authorization code missing.', flash[:alert]
  end

  def test_callback_exchanges_github_code
    log_user('admin', 'admin')

    mock_response = mock('response')
    mock_response.stubs(:is_a?).with(Net::HTTPSuccess).returns(true)
    mock_response.stubs(:body).returns(JSON.generate({
      access_token: 'gh-access-token',
      refresh_token: 'gh-refresh-token',
      expires_in: 28800
    }))
    Net::HTTP.stubs(:post_form).returns(mock_response)

    get '/dev_integrations/github/oauth/start'
    state = oauth_state_from_redirect(response.location)

    get "/dev_integrations/github/oauth/callback?code=test-code&state=#{state}"
    assert_redirected_to '/settings/plugin/redmine_dev_integration'
    assert_equal 'Successfully connected Github OAuth.', flash[:notice]
  end

  def test_callback_exchanges_gitlab_code
    log_user('admin', 'admin')

    mock_http = mock('http')
    mock_http.stubs(:use_ssl=)
    mock_http.stubs(:request).returns(build_gitlab_token_success_response)
    Net::HTTP.stubs(:new).returns(mock_http)

    get '/dev_integrations/gitlab/oauth/start'
    state = oauth_state_from_redirect(response.location)

    get "/dev_integrations/gitlab/oauth/callback?code=test-code&state=#{state}"
    assert_redirected_to '/settings/plugin/redmine_dev_integration'
    assert_equal 'Successfully connected Gitlab OAuth.', flash[:notice]
  end

  def test_callback_handles_token_exchange_error
    log_user('admin', 'admin')

    mock_http = mock('http')
    mock_http.stubs(:use_ssl=)
    mock_http.stubs(:request).returns(build_gitlab_token_error_response)
    Net::HTTP.stubs(:new).returns(mock_http)

    get '/dev_integrations/gitlab/oauth/start'
    state = oauth_state_from_redirect(response.location)

    get "/dev_integrations/gitlab/oauth/callback?code=test-code&state=#{state}"
    assert_redirected_to '/settings/plugin/redmine_dev_integration'
    assert_match /OAuth error/, flash[:alert]
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

  def test_disconnect_rejects_non_admin
    log_user('jsmith', 'jsmith')
    post '/dev_integrations/github/oauth/disconnect'
    assert_response :forbidden
  end

  private

  def build_gitlab_token_success_response
    response = mock('response')
    response.stubs(:is_a?).with(Net::HTTPSuccess).returns(true)
    response.stubs(:body).returns(JSON.generate({
      access_token: 'gl-access-token',
      refresh_token: 'gl-refresh-token',
      expires_in: 7200
    }))
    response
  end

  def build_gitlab_token_error_response
    response = mock('response')
    response.stubs(:is_a?).with(Net::HTTPSuccess).returns(false)
    response.stubs(:code).returns('400')
    response
  end
end
