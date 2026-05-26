# frozen_string_literal: true

module RedmineDevIntegration
  class WebhookRegistrationService
    Result = Struct.new(:status, :message, keyword_init: true) do
      def success?
        status == :success
      end

      def error?
        status == :error
      end
    end

    def register(repository:, redmine_webhook_url:)
      case repository.provider.to_s
      when 'github'
        register_github_webhook(repository, redmine_webhook_url)
      when 'gitlab'
        register_gitlab_webhook(repository, redmine_webhook_url)
      else
        Result.new(status: :error, message: "Unsupported provider: #{repository.provider}")
      end
    end

    private

    def register_github_webhook(repository, redmine_webhook_url)
      secret = github_webhook_secret
      return Result.new(status: :error, message: 'GitHub webhook secret is not configured') if secret.blank?

      client = ProviderClients::GitHubClient.new
      return Result.new(status: :error, message: 'GitHub API token is missing') if client.credentials_missing?

      begin
        existing = find_existing_webhook(client, repository, redmine_webhook_url)

        if existing
          updated = client.update_webhook(
            repository: repository,
            webhook_id: existing['id'],
            url: redmine_webhook_url,
            secret: secret
          )
          repository.update!(
            provider_webhook_id: existing['id'].to_s,
            webhook_registered_at: Time.current,
            webhook_registration_status: 'registered'
          )
          Result.new(status: :success, message: 'Webhook updated')
        else
          created = client.create_webhook(
            repository: repository,
            url: redmine_webhook_url,
            secret: secret
          )
          repository.update!(
            provider_webhook_id: created['id'].to_s,
            webhook_registered_at: Time.current,
            webhook_registration_status: 'registered'
          )
          Result.new(status: :success, message: 'Webhook created')
        end
      rescue StandardError => e
        error_msg = e.respond_to?(:response) && e.response.respond_to?(:body) ? e.response.body.to_s.truncate(500) : e.message
        repository.update!(
          webhook_registered_at: Time.current,
          webhook_registration_status: 'error'
        )
        Result.new(status: :error, message: error_msg)
      end
    end

    def register_gitlab_webhook(repository, redmine_webhook_url)
      token = gitlab_webhook_token
      return Result.new(status: :error, message: 'GitLab webhook secret token is not configured') if token.blank?

      client = ProviderClients::GitLabClient.new
      return Result.new(status: :error, message: 'GitLab API token is missing') if client.credentials_missing?

      begin
        existing = find_existing_webhook(client, repository, redmine_webhook_url)

        if existing
          client.update_webhook(
            repository: repository,
            webhook_id: existing['id'],
            url: redmine_webhook_url,
            token: token
          )
          repository.update!(
            provider_webhook_id: existing['id'].to_s,
            webhook_registered_at: Time.current,
            webhook_registration_status: 'registered'
          )
          Result.new(status: :success, message: 'Webhook updated')
        else
          created = client.create_webhook(
            repository: repository,
            url: redmine_webhook_url,
            token: token
          )
          repository.update!(
            provider_webhook_id: created['id'].to_s,
            webhook_registered_at: Time.current,
            webhook_registration_status: 'registered'
          )
          Result.new(status: :success, message: 'Webhook created')
        end
      rescue StandardError => e
        error_msg = e.respond_to?(:response) && e.response.respond_to?(:body) ? e.response.body.to_s.truncate(500) : e.message
        repository.update!(
          webhook_registered_at: Time.current,
          webhook_registration_status: 'error'
        )
        Result.new(status: :error, message: error_msg)
      end
    end

    def find_existing_webhook(client, repository, redmine_webhook_url)
      hooks = client.list_webhooks(repository: repository).select do |hook|
        hook.dig('config', 'url') == redmine_webhook_url || hook.dig('config', 'url').to_s.include?(host_from_url(redmine_webhook_url))
      end

      hooks.first
    rescue StandardError
      nil
    end

    def host_from_url(url)
      URI.parse(url).host
    rescue StandardError
      nil
    end

    def github_webhook_secret
      setting = Setting.plugin_redmine_dev_integration
      return nil unless setting.is_a?(Hash)

      setting['github_webhook_secret'].presence || setting[:github_webhook_secret].presence
    end

    def gitlab_webhook_token
      setting = Setting.plugin_redmine_dev_integration
      return nil unless setting.is_a?(Hash)

      setting['gitlab_webhook_token'].presence || setting[:gitlab_webhook_token].presence
    end
  end
end
