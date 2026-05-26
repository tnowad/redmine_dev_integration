# frozen_string_literal: true

module DevIntegrations
  class BitbucketWebhooksController < ApplicationController
    before_action :ensure_bitbucket_provider_enabled!
    before_action :verify_bitbucket_signature!

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

    def verify_bitbucket_signature!
      verifier = RedmineDevIntegration::BitbucketWebhookSignatureVerifier.new(secret: bitbucket_webhook_secret)

      return if verifier.valid?(payload: request.raw_post, signature: request.headers['X-Hub-Signature-256'])

      render json: {error: 'invalid signature'}, status: :unauthorized
    end

    def ensure_bitbucket_provider_enabled!
      return if bitbucket_provider_enabled?

      render json: {error: 'bitbucket provider disabled'}, status: :forbidden
    end

    def bitbucket_webhook_secret
      setting = Setting.plugin_redmine_dev_integration
      setting.is_a?(Hash) ? setting['bitbucket_webhook_secret'].presence || setting[:bitbucket_webhook_secret].presence : nil
    end

    def bitbucket_provider_enabled?
      setting = Setting.plugin_redmine_dev_integration
      value = setting.is_a?(Hash) ? setting['bitbucket_provider_enabled'] || setting[:bitbucket_provider_enabled] : nil
      return true if value.nil?

      value == '1' || value == true
    end

    def find_or_initialize_event
      ExternalProviderEvent.find_or_initialize_by(
        provider: 'bitbucket',
        delivery_id: bitbucket_delivery_id,
        event_type: request.headers['X-Event-Key'].to_s
      )
    end

    def bitbucket_delivery_id
      request.headers['X-Request-Id'].presence ||
        request.headers['X-Event-Key'].presence ||
        ''
    end
  end
end
