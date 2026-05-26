# frozen_string_literal: true

module RedmineDevIntegration
  module Oauth
    class GithubAuthorizationService
      TOKEN_URL = 'https://github.com/login/oauth/access_token'.freeze

      def self.call(code:)
        settings = Setting.plugin_redmine_dev_integration
        client_id = settings['github_oauth_client_id']
        client_secret = EncryptedSetting.decrypt(settings['github_oauth_client_secret'])
        raise 'GitHub OAuth client credentials not configured' if client_id.blank? || client_secret.blank?

        uri = URI(TOKEN_URL)
        response = Net::HTTP.post_form(uri, {
          client_id: client_id,
          client_secret: client_secret,
          code: code,
          redirect_uri: callback_url
        })

        unless response.is_a?(Net::HTTPSuccess)
          raise "GitHub token exchange failed: #{response.code}"
        end

        data = JSON.parse(response.body)
        access_token = data['access_token']
        raise 'No access token in GitHub response' if access_token.blank?

        TokenStore.store(
          provider: 'github',
          access_token: access_token,
          refresh_token: data['refresh_token'],
          expires_in: data['expires_in']
        )
      end

      def self.callback_url
        "#{Setting.protocol}://#{Setting.host_name}/dev_integrations/github/oauth/callback"
      end
    end
  end
end
