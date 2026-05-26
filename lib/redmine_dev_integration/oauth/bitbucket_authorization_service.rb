# frozen_string_literal: true

module RedmineDevIntegration
  module Oauth
    class BitbucketAuthorizationService
      TOKEN_URL = 'https://bitbucket.org/site/oauth2/access_token'.freeze
      AUTHORIZE_URL = 'https://bitbucket.org/site/oauth2/authorize'.freeze

      def self.call(code:)
        settings = Setting.plugin_redmine_dev_integration
        client_id = settings['bitbucket_oauth_key']
        client_secret = EncryptedSetting.decrypt(settings['bitbucket_oauth_secret'])
        raise 'Bitbucket OAuth client credentials not configured' if client_id.blank? || client_secret.blank?

        uri = URI(TOKEN_URL)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Post.new(uri)
        request.basic_auth(client_id, client_secret)
        request.set_form_data({
          grant_type: 'authorization_code',
          code: code,
          redirect_uri: callback_url
        })

        response = http.request(request)
        unless response.is_a?(Net::HTTPSuccess)
          raise "Bitbucket token exchange failed: #{response.code}"
        end

        data = JSON.parse(response.body)
        access_token = data['access_token']
        raise 'No access token in Bitbucket response' if access_token.blank?

        TokenStore.store(
          provider: 'bitbucket',
          access_token: access_token,
          refresh_token: data['refresh_token'],
          expires_in: data['expires_in']
        )
      end

      def self.callback_url
        "#{Setting.protocol}://#{Setting.host_name}/dev_integrations/bitbucket/oauth/callback"
      end
    end
  end
end
