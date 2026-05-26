# frozen_string_literal: true

module RedmineDevIntegration
  module Oauth
    class GitlabAuthorizationService
      def self.call(code:)
        settings = Setting.plugin_redmine_dev_integration
        app_id = settings['gitlab_oauth_app_id']
        app_secret = EncryptedSetting.decrypt(settings['gitlab_oauth_app_secret'])
        raise 'GitLab OAuth app credentials not configured' if app_id.blank? || app_secret.blank?

        uri = URI("#{base_url}/oauth/token")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'

        request = Net::HTTP::Post.new(uri)
        request.set_form_data({
          client_id: app_id,
          client_secret: app_secret,
          code: code,
          grant_type: 'authorization_code',
          redirect_uri: callback_url
        })

        response = http.request(request)
        unless response.is_a?(Net::HTTPSuccess)
          raise "GitLab token exchange failed: #{response.code}"
        end

        data = JSON.parse(response.body)
        access_token = data['access_token']
        raise 'No access token in GitLab response' if access_token.blank?

        TokenStore.store(
          provider: 'gitlab',
          access_token: access_token,
          refresh_token: data['refresh_token'],
          expires_in: data['expires_in']
        )
      end

      def self.base_url
        settings = Setting.plugin_redmine_dev_integration
        (settings['gitlab_base_url'].presence || 'https://gitlab.com').delete_suffix('/')
      end

      def self.callback_url
        "#{Setting.protocol}://#{Setting.host_name}/dev_integrations/gitlab/oauth/callback"
      end
    end
  end
end
