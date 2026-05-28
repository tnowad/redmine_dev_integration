# frozen_string_literal: true

module DevIntegrations
  class GitlabWebhooksController < ApplicationController
    before_action :ensure_gitlab_provider_enabled!
    before_action :verify_gitlab_token!

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

    def verify_gitlab_token!
      verifier = RedmineDevIntegration::GitlabWebhookTokenVerifier.new(expected_token: gitlab_webhook_token)

      return if verifier.valid?(token: request.headers['X-Gitlab-Token'])

      render json: {error: 'invalid token'}, status: :unauthorized
    end

    def ensure_gitlab_provider_enabled!
      return if gitlab_provider_enabled?

      render json: {error: 'gitlab provider disabled'}, status: :forbidden
    end

    def gitlab_webhook_token
      setting = Setting.plugin_redmine_dev_integration
      return nil unless setting.is_a?(Hash)

      setting['gitlab_webhook_token'].presence || setting[:gitlab_webhook_token].presence
    end

    def gitlab_provider_enabled?
      setting = Setting.plugin_redmine_dev_integration
      value = setting.is_a?(Hash) ? setting['gitlab_provider_enabled'] || setting[:gitlab_provider_enabled] : nil
      return true if value.nil?

      value == '1' || value == true
    end

    def find_or_initialize_event
      ExternalProviderEvent.find_or_initialize_by(
        provider: 'gitlab',
        delivery_id: gitlab_delivery_id,
        event_type: request.headers['X-Gitlab-Event'].to_s
      )
    end

    def gitlab_delivery_id
      request.headers['Idempotency-Key'].presence ||
        request.headers['X-Gitlab-Event-UUID'].presence ||
        request.headers['X-Gitlab-Webhook-UUID'].presence ||
        ''
    end

    def extract_repository_id(raw_post)
      payload = JSON.parse(raw_post)
      (payload.dig('project', 'id') || payload['project_id'] || payload.dig('repository', 'id'))&.to_s
    rescue JSON::ParserError, TypeError
      nil
    end
  end
end
