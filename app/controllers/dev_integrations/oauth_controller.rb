# frozen_string_literal: true

module DevIntegrations
  class OauthController < ApplicationController
    skip_before_action :check_if_login_required, raise: false
    before_action :require_admin
    before_action :validate_provider, only: %i[start callback disconnect]

    def start
      case params[:provider]
      when 'github'
        redirect_to github_authorize_url, allow_other_host: true
      when 'gitlab'
        redirect_to gitlab_authorize_url, allow_other_host: true
      when 'bitbucket'
        redirect_to bitbucket_authorize_url, allow_other_host: true
      end
    end

    def callback
      state = params[:state]
      if state.blank? || !RedmineDevIntegration::OauthStateStore.verify(state, params[:provider])
        redirect_to plugin_settings_path, alert: t('redmine_dev_integration.oauth.invalid_state')
        return
      end

      if params[:code].blank?
        redirect_to plugin_settings_path, alert: t('redmine_dev_integration.oauth.missing_code')
        return
      end

      case params[:provider]
      when 'github'
        RedmineDevIntegration::Oauth::GithubAuthorizationService.call(code: params[:code])
      when 'gitlab'
        RedmineDevIntegration::Oauth::GitlabAuthorizationService.call(code: params[:code])
      when 'bitbucket'
        RedmineDevIntegration::Oauth::BitbucketAuthorizationService.call(code: params[:code])
      end

      redirect_to plugin_settings_path, notice: t('redmine_dev_integration.oauth.connected', provider: params[:provider].capitalize)
    rescue StandardError => e
      redirect_to plugin_settings_path, alert: t('redmine_dev_integration.oauth.error', message: e.message)
    end

    def disconnect
      case params[:provider]
      when 'github'
        clear_oauth_settings('github')
      when 'gitlab'
        clear_oauth_settings('gitlab')
      when 'bitbucket'
        clear_oauth_settings('bitbucket')
      end
      redirect_to plugin_settings_path, notice: t('redmine_dev_integration.oauth.disconnected', provider: params[:provider].capitalize)
    end

    private

    def validate_provider
      render_403 unless %w[github gitlab bitbucket].include?(params[:provider])
    end

    def github_authorize_url
      settings = Setting.plugin_redmine_dev_integration
      client_id = settings['github_oauth_client_id']
      state = RedmineDevIntegration::OauthStateStore.generate('github')

      params = {
        client_id: client_id,
        redirect_uri: github_callback_url,
        scope: 'repo admin:repo_hook',
        state: state
      }
      "https://github.com/login/oauth/authorize?#{params.to_query}"
    end

    def gitlab_authorize_url
      settings = Setting.plugin_redmine_dev_integration
      app_id = settings['gitlab_oauth_app_id']
      state = RedmineDevIntegration::OauthStateStore.generate('gitlab')

      params = {
        client_id: app_id,
        redirect_uri: gitlab_callback_url,
        scope: 'api',
        state: state
      }
      "#{gitlab_base_url}/oauth/authorize?#{params.to_query}"
    end

    def github_callback_url
      "#{Setting.protocol}://#{Setting.host_name}/dev_integrations/github/oauth/callback"
    end

    def gitlab_callback_url
      "#{Setting.protocol}://#{Setting.host_name}/dev_integrations/gitlab/oauth/callback"
    end

    def bitbucket_authorize_url
      settings = Setting.plugin_redmine_dev_integration
      key = settings['bitbucket_oauth_key']
      state = RedmineDevIntegration::OauthStateStore.generate('bitbucket')

      params = {
        client_id: key,
        response_type: 'code',
        redirect_uri: bitbucket_callback_url,
        state: state
      }
      "https://bitbucket.org/site/oauth2/authorize?#{params.to_query}"
    end

    def bitbucket_callback_url
      "#{Setting.protocol}://#{Setting.host_name}/dev_integrations/bitbucket/oauth/callback"
    end

    def gitlab_base_url
      settings = Setting.plugin_redmine_dev_integration
      base = settings['gitlab_base_url'].presence || 'https://gitlab.com'
      base.delete_suffix('/')
    end

    def plugin_settings_path
      '/settings/plugin/redmine_dev_integration'
    end

    def clear_oauth_settings(provider)
      settings_hash = (Setting.plugin_redmine_dev_integration || {}).merge(
        "#{provider}_oauth_access_token" => '',
        "#{provider}_oauth_refresh_token" => '',
        "#{provider}_oauth_connected_at" => nil,
        "#{provider}_oauth_token_expires_at" => nil
      )
      Setting.plugin_redmine_dev_integration = settings_hash
    end
  end
end
