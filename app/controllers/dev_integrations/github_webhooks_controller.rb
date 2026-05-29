# frozen_string_literal: true

module DevIntegrations
  class GithubWebhooksController < ApplicationController
    before_action :ensure_github_provider_enabled!
    before_action :verify_github_signature!

    skip_before_action :check_if_login_required, raise: false
    skip_before_action :verify_authenticity_token

    def create
      event = find_or_initialize_event

      if event.persisted?
        head :ok
        return
      end

      event.payload = request.raw_post
      event.status = 'pending'
      event.provider_repository_id = extract_repository_id(request.raw_post)

      if event.save
        ExternalProviderEventJob.perform_later(event.id)
        render json: {status: 'accepted'}, status: :accepted
      else
        render json: {error: 'unable to store event'}, status: :unprocessable_entity
      end
    rescue ActiveRecord::RecordNotUnique
      head :ok
    end

    private

    def verify_github_signature!
      verifier = RedmineDevIntegration::GithubWebhookSignatureVerifier.new(secret: github_webhook_secret)

      return if verifier.valid?(payload: request.raw_post, signature: request.headers['X-Hub-Signature-256'])

      render json: {error: 'invalid signature'}, status: :unauthorized
    end

    def ensure_github_provider_enabled!
      return if github_provider_enabled?

      render json: {error: 'github provider disabled'}, status: :forbidden
    end

    def github_webhook_secret
      setting = Setting.plugin_redmine_dev_integration
      setting.is_a?(Hash) ? setting['github_webhook_secret'].presence || setting[:github_webhook_secret].presence : nil
    end

    def github_provider_enabled?
      setting = Setting.plugin_redmine_dev_integration
      value = setting.is_a?(Hash) ? setting['github_provider_enabled'] || setting[:github_provider_enabled] : nil
      return true if value.nil?

      value == '1' || value == true
    end

    def find_or_initialize_event
      ExternalProviderEvent.find_or_initialize_by(
        provider: 'github',
        delivery_id: request.headers['X-Github-Delivery'].to_s,
        event_type: request.headers['X-Github-Event'].to_s
      )
    end

    def extract_repository_id(raw_post)
      payload = JSON.parse(raw_post)
      payload.dig('repository', 'id')&.to_s
    rescue JSON::ParserError, TypeError
      nil
    end
  end
end
