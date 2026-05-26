# frozen_string_literal: true

require_relative '../../test_helper'

module RedmineDevIntegration
  module Oauth
    class GitlabAuthorizationServiceTest < ActiveSupport::TestCase
      def setup
        @app_id = 'gl-app-id'
        @app_secret = 'gl-app-secret'
        @encrypted_secret = EncryptedSetting.encrypt(@app_secret)
        Setting.stubs(:protocol).returns('https')
        Setting.stubs(:host_name).returns('redmine.example.com')
      end

      def test_exchanges_code_for_token
        settings = {
          'gitlab_oauth_app_id' => @app_id,
          'gitlab_oauth_app_secret' => @encrypted_secret,
          'gitlab_base_url' => 'https://gitlab.example.com'
        }
        Setting.stubs(:plugin_redmine_dev_integration).returns(settings)

        Net::HTTP.any_instance.stubs(:request).returns(build_success_response)

        Setting.expects(:plugin_redmine_dev_integration=).with do |hash|
          encrypted = hash['gitlab_oauth_access_token']
          EncryptedSetting.decrypt(encrypted) == 'gl-access-token'
        end

        GitlabAuthorizationService.call(code: 'test-code')
      end

      def test_uses_default_base_url_for_gitlab_com
        settings = {
          'gitlab_oauth_app_id' => @app_id,
          'gitlab_oauth_app_secret' => @encrypted_secret
        }
        Setting.stubs(:plugin_redmine_dev_integration).returns(settings)

        assert_equal 'https://gitlab.com', GitlabAuthorizationService.base_url
      end

      def test_raises_when_app_id_missing
        Setting.stubs(:plugin_redmine_dev_integration).returns({
          'gitlab_oauth_app_id' => '',
          'gitlab_oauth_app_secret' => @encrypted_secret
        })

        assert_raises RuntimeError do
          GitlabAuthorizationService.call(code: 'test-code')
        end
      end

      def test_raises_when_app_secret_missing
        Setting.stubs(:plugin_redmine_dev_integration).returns({
          'gitlab_oauth_app_id' => @app_id,
          'gitlab_oauth_app_secret' => EncryptedSetting.encrypt('')
        })

        assert_raises RuntimeError do
          GitlabAuthorizationService.call(code: 'test-code')
        end
      end

      def test_raises_on_gitlab_error_response
        Setting.stubs(:plugin_redmine_dev_integration).returns({
          'gitlab_oauth_app_id' => @app_id,
          'gitlab_oauth_app_secret' => @encrypted_secret,
          'gitlab_base_url' => 'https://gitlab.example.com'
        })

        mock_http = mock('http')
        mock_http.stubs(:use_ssl=)
        mock_http.stubs(:request).returns(build_error_response)

        Net::HTTP.stubs(:new).returns(mock_http)

        assert_raises RuntimeError do
          GitlabAuthorizationService.call(code: 'test-code')
        end
      end

      def test_raises_when_no_access_token_in_response
        Setting.stubs(:plugin_redmine_dev_integration).returns({
          'gitlab_oauth_app_id' => @app_id,
          'gitlab_oauth_app_secret' => @encrypted_secret,
          'gitlab_base_url' => 'https://gitlab.example.com'
        })

        mock_http = mock('http')
        mock_http.stubs(:use_ssl=)
        mock_http.stubs(:request).returns(build_empty_token_response)

        Net::HTTP.stubs(:new).returns(mock_http)

        assert_raises RuntimeError do
          GitlabAuthorizationService.call(code: 'test-code')
        end
      end

      def test_self_hosted_base_url_normalization
        settings = {
          'gitlab_oauth_app_id' => @app_id,
          'gitlab_oauth_app_secret' => @encrypted_secret,
          'gitlab_base_url' => 'https://gitlab.example.com/'
        }
        Setting.stubs(:plugin_redmine_dev_integration).returns(settings)

        assert_equal 'https://gitlab.example.com', GitlabAuthorizationService.base_url
      end

      def test_callback_url_uses_redmine_settings
        assert_equal 'https://redmine.example.com/dev_integrations/gitlab/oauth/callback',
                     GitlabAuthorizationService.callback_url
      end

      private

      def build_success_response
        response = mock('response')
        response.stubs(:is_a?).with(Net::HTTPSuccess).returns(true)
        response.stubs(:body).returns(JSON.generate({
          access_token: 'gl-access-token',
          refresh_token: 'gl-refresh-token',
          expires_in: 7200
        }))
        response
      end

      def build_error_response
        response = mock('response')
        response.stubs(:is_a?).with(Net::HTTPSuccess).returns(false)
        response.stubs(:code).returns('400')
        response
      end

      def build_empty_token_response
        response = mock('response')
        response.stubs(:is_a?).with(Net::HTTPSuccess).returns(true)
        response.stubs(:body).returns(JSON.generate({error: 'something'}))
        response
      end
    end
  end
end
