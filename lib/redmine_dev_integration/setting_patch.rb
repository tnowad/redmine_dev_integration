# frozen_string_literal: true

module RedmineDevIntegration
  module SettingPatch
    def plugin_redmine_dev_integration=(settings)
      settings = {} if settings.nil?
      settings = settings.to_h if settings.respond_to?(:to_h) && !settings.is_a?(Hash)
      settings = settings.stringify_keys if settings.respond_to?(:stringify_keys)

      preserve_setting!(settings, 'github_webhook_secret')
      preserve_setting!(settings, 'github_api_token')
      preserve_setting!(settings, 'gitlab_webhook_token')
      preserve_setting!(settings, 'gitlab_api_token')
      preserve_setting!(settings, 'bitbucket_webhook_secret')
      preserve_setting!(settings, 'bitbucket_api_token')
      preserve_setting!(settings, 'github_oauth_client_secret')
      preserve_setting!(settings, 'gitlab_oauth_app_secret')
      preserve_setting!(settings, 'bitbucket_oauth_secret')
      encrypted_setting!(settings, 'github_oauth_client_secret')
      encrypted_setting!(settings, 'github_oauth_access_token')
      encrypted_setting!(settings, 'github_oauth_refresh_token')
      encrypted_setting!(settings, 'gitlab_oauth_app_secret')
      encrypted_setting!(settings, 'gitlab_oauth_access_token')
      encrypted_setting!(settings, 'gitlab_oauth_refresh_token')
      encrypted_setting!(settings, 'bitbucket_oauth_secret')
      encrypted_setting!(settings, 'bitbucket_oauth_access_token')
      encrypted_setting!(settings, 'bitbucket_oauth_refresh_token')

      super(settings)
    end

    private

    def preserve_setting!(settings, key)
      return unless settings.is_a?(Hash)

      submitted_value = settings[key] || settings[key.to_sym]
      return if submitted_value.present?

      current_settings = plugin_redmine_dev_integration
      existing_value = if current_settings.is_a?(Hash)
        current_settings[key].presence || current_settings[key.to_sym].presence
      end

      settings[key] = existing_value if existing_value.present?
    end

    def encrypted_setting!(settings, key)
      return unless settings.is_a?(Hash)

      submitted_value = settings[key] || settings[key.to_sym]
      if submitted_value.present?
        settings[key] = if RedmineDevIntegration::EncryptedSetting.decrypt(submitted_value)
                          submitted_value
                        else
                          RedmineDevIntegration::EncryptedSetting.encrypt(submitted_value)
                        end
      else
        current_settings = plugin_redmine_dev_integration
        existing_value = if current_settings.is_a?(Hash)
          current_settings[key].presence || current_settings[key.to_sym].presence
        end
        settings[key] = existing_value if existing_value.present?
      end
    end
  end
end
