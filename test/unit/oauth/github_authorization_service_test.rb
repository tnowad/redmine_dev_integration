# frozen_string_literal: true

require_relative '../../test_helper'

module RedmineDevIntegration
  module Oauth
    class GithubAuthorizationServiceTest < ActiveSupport::TestCase
      def setup
        @client_id = 'gh-client-id'
        @client_secret = 'gh-client-secret'
        @encrypted_secret = EncryptedSetting.encrypt(@client_secret)
        Setting.stubs(:protocol).returns('https')
        Setting.stubs(:host_name).returns('redmine.example.com')
      end

      def test_exchanges_code_for_token
        settings = {
          'github_oauth_client_id' => @client_id,
          'github_oauth_client_secret' => @encrypted_secret
        }
        Setting.stubs(:plugin_redmine_dev_integration).returns(settings)

        mock_response = mock('response')
        mock_response.stubs(:is_a?).with(Net::HTTPSuccess).returns(true)
        mock_response.stubs(:body).returns(JSON.generate({
          access_token: 'gh-access-token',
          refresh_token: 'gh-refresh-token',
          expires_in: 28800
        }))

        Net::HTTP.stubs(:post_form).returns(mock_response)
        Setting.expects(:plugin_redmine_dev_integration=).with do |hash|
          encrypted = hash['github_oauth_access_token']
          EncryptedSetting.decrypt(encrypted) == 'gh-access-token'
        end

        GithubAuthorizationService.call(code: 'test-code')
      end

      def test_raises_when_client_id_missing
        Setting.stubs(:plugin_redmine_dev_integration).returns({
          'github_oauth_client_id' => '',
          'github_oauth_client_secret' => @encrypted_secret
        })

        assert_raises RuntimeError do
          GithubAuthorizationService.call(code: 'test-code')
        end
      end

      def test_raises_when_client_secret_missing
        Setting.stubs(:plugin_redmine_dev_integration).returns({
          'github_oauth_client_id' => @client_id,
          'github_oauth_client_secret' => EncryptedSetting.encrypt('')
        })

        assert_raises RuntimeError do
          GithubAuthorizationService.call(code: 'test-code')
        end
      end

      def test_raises_on_github_error_response
        Setting.stubs(:plugin_redmine_dev_integration).returns({
          'github_oauth_client_id' => @client_id,
          'github_oauth_client_secret' => @encrypted_secret
        })

        mock_response = mock('response')
        mock_response.stubs(:is_a?).with(Net::HTTPSuccess).returns(false)
        mock_response.stubs(:code).returns('400')

        Net::HTTP.stubs(:post_form).returns(mock_response)

        assert_raises RuntimeError do
          GithubAuthorizationService.call(code: 'test-code')
        end
      end

      def test_raises_when_no_access_token_in_response
        Setting.stubs(:plugin_redmine_dev_integration).returns({
          'github_oauth_client_id' => @client_id,
          'github_oauth_client_secret' => @encrypted_secret
        })

        mock_response = mock('response')
        mock_response.stubs(:is_a?).with(Net::HTTPSuccess).returns(true)
        mock_response.stubs(:body).returns(JSON.generate({error: 'something'}))

        Net::HTTP.stubs(:post_form).returns(mock_response)

        assert_raises RuntimeError do
          GithubAuthorizationService.call(code: 'test-code')
        end
      end

      def test_callback_url_uses_redmine_settings
        assert_equal 'https://redmine.example.com/dev_integrations/github/oauth/callback',
                     GithubAuthorizationService.callback_url
      end
    end
  end
end
