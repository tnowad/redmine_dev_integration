# frozen_string_literal: true

require_relative '../../test_helper'

module RedmineDevIntegration
  module Oauth
    class TokenStoreTest < ActiveSupport::TestCase
      def setup
        @base_settings = {
          'github_webhook_secret' => 'existing-secret'
        }
      end

      def test_store_saves_encrypted_access_token
        Setting.stubs(:plugin_redmine_dev_integration).returns(@base_settings)
        Setting.expects(:plugin_redmine_dev_integration=).with do |hash|
          hash['github_webhook_secret'] == 'existing-secret' &&
            EncryptedSetting.decrypt(hash['github_oauth_access_token']) == 'gh-token'
        end

        TokenStore.store(provider: 'github', access_token: 'gh-token')
      end

      def test_store_saves_encrypted_refresh_token
        Setting.stubs(:plugin_redmine_dev_integration).returns(@base_settings)
        Setting.expects(:plugin_redmine_dev_integration=).with do |hash|
          EncryptedSetting.decrypt(hash['github_oauth_refresh_token']) == 'gh-refresh'
        end

        TokenStore.store(provider: 'github', access_token: 'gh-token', refresh_token: 'gh-refresh')
      end

      def test_store_sets_connected_at
        Setting.stubs(:plugin_redmine_dev_integration).returns(@base_settings)
        Setting.expects(:plugin_redmine_dev_integration=).with do |hash|
          hash['github_oauth_connected_at'].present?
        end

        TokenStore.store(provider: 'github', access_token: 'gh-token')
      end

      def test_store_sets_expires_at_when_provided
        Setting.stubs(:plugin_redmine_dev_integration).returns(@base_settings)
        freeze_time = Time.current

        Setting.expects(:plugin_redmine_dev_integration=).with do |hash|
          hash['github_oauth_token_expires_at'].present? &&
            hash['github_oauth_token_expires_at'] == (freeze_time + 3600.seconds).iso8601
        end

        TokenStore.store(provider: 'github', access_token: 'gh-token', expires_in: 3600)
      end

      def test_store_sets_nil_expires_at_when_not_provided
        Setting.stubs(:plugin_redmine_dev_integration).returns(@base_settings)

        Setting.expects(:plugin_redmine_dev_integration=).with do |hash|
          hash['github_oauth_token_expires_at'].nil?
        end

        TokenStore.store(provider: 'github', access_token: 'gh-token')
      end

      def test_access_token_decrypts_stored_value
        encrypted = EncryptedSetting.encrypt('gh-access-token')
        Setting.stubs(:plugin_redmine_dev_integration).returns({
          'github_oauth_access_token' => encrypted
        })

        assert_equal 'gh-access-token', TokenStore.access_token('github')
      end

      def test_access_token_returns_nil_when_not_set
        Setting.stubs(:plugin_redmine_dev_integration).returns({})
        assert_nil TokenStore.access_token('github')
      end

      def test_refresh_token_decrypts_stored_value
        encrypted = EncryptedSetting.encrypt('gh-refresh-token')
        Setting.stubs(:plugin_redmine_dev_integration).returns({
          'github_oauth_refresh_token' => encrypted
        })

        assert_equal 'gh-refresh-token', TokenStore.refresh_token('github')
      end

      def test_refresh_token_returns_nil_when_not_set
        Setting.stubs(:plugin_redmine_dev_integration).returns({})
        assert_nil TokenStore.refresh_token('github')
      end

      def test_connected_returns_true_when_token_exists
        encrypted = EncryptedSetting.encrypt('gh-access-token')
        Setting.stubs(:plugin_redmine_dev_integration).returns({
          'github_oauth_access_token' => encrypted
        })

        assert TokenStore.connected?('github')
      end

      def test_connected_returns_false_when_no_token
        Setting.stubs(:plugin_redmine_dev_integration).returns({})
        refute TokenStore.connected?('github')
      end

      def test_store_preserves_other_provider_tokens
        github_encrypted = EncryptedSetting.encrypt('gh-token')
        Setting.stubs(:plugin_redmine_dev_integration).returns({
          'github_oauth_access_token' => github_encrypted
        })

        Setting.expects(:plugin_redmine_dev_integration=).with do |hash|
          EncryptedSetting.decrypt(hash['github_oauth_access_token']) == 'gh-token' &&
            EncryptedSetting.decrypt(hash['gitlab_oauth_access_token']) == 'gl-token'
        end

        TokenStore.store(provider: 'gitlab', access_token: 'gl-token')
      end

      def test_store_with_gitlab_provider
        Setting.stubs(:plugin_redmine_dev_integration).returns(@base_settings)
        Setting.expects(:plugin_redmine_dev_integration=).with do |hash|
          EncryptedSetting.decrypt(hash['gitlab_oauth_access_token']) == 'gl-token'
        end

        TokenStore.store(provider: 'gitlab', access_token: 'gl-token')
      end

      def test_access_token_with_nil_encrypted_value
        Setting.stubs(:plugin_redmine_dev_integration).returns({
          'github_oauth_access_token' => nil
        })
        assert_nil TokenStore.access_token('github')
      end
    end
  end
end
