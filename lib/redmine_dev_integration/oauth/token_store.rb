# frozen_string_literal: true

module RedmineDevIntegration
  module Oauth
    class TokenStore
      def self.store(provider:, access_token:, refresh_token: nil, expires_in: nil)
        settings = Setting.plugin_redmine_dev_integration.to_h.merge(
          "#{provider}_oauth_access_token" => EncryptedSetting.encrypt(access_token),
          "#{provider}_oauth_refresh_token" => EncryptedSetting.encrypt(refresh_token),
          "#{provider}_oauth_connected_at" => Time.current.iso8601,
          "#{provider}_oauth_token_expires_at" => expires_in ? expires_in.seconds.from_now.iso8601 : nil
        )
        Setting.plugin_redmine_dev_integration = settings
      end

      def self.access_token(provider)
        encrypted = Setting.plugin_redmine_dev_integration.try(:[], "#{provider}_oauth_access_token")
        EncryptedSetting.decrypt(encrypted)
      end

      def self.refresh_token(provider)
        encrypted = Setting.plugin_redmine_dev_integration.try(:[], "#{provider}_oauth_refresh_token")
        EncryptedSetting.decrypt(encrypted)
      end

      def self.connected?(provider)
        access_token(provider).present?
      end
    end
  end
end
