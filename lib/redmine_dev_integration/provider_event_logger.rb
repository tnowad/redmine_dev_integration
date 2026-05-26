# frozen_string_literal: true

require 'json'

module RedmineDevIntegration
  class ProviderEventLogger
    LOG_PREFIX = 'redmine_dev_integration.provider_event'

    def call(external_provider_event, status:, duration_ms:, error: nil, logger: Rails.logger)
      payload = build_payload(external_provider_event, status: status, duration_ms: duration_ms, error: error)
      logger.info("#{LOG_PREFIX} #{JSON.generate(payload)}")
    rescue StandardError
      nil
    end

    private

    def build_payload(external_provider_event, status:, duration_ms:, error:)
      {
        provider: external_provider_event.provider,
        delivery_id: external_provider_event.delivery_id,
        event_type: external_provider_event.event_type,
        external_repository_id: external_repository_id(external_provider_event),
        status: status,
        duration_ms: duration_ms,
        error_class: error&.class&.name,
        error_message: error&.message
      }
    end

    def external_repository_id(external_provider_event)
      repository_id = payload_repository_id(external_provider_event.payload)
      return nil if repository_id.blank?

      ExternalRepository.find_by(
        provider: external_provider_event.provider,
        provider_repository_id: repository_id.to_s
      )&.id
    rescue StandardError
      nil
    end

    def payload_repository_id(payload)
      parsed_payload = parse_payload(payload)
      repository = parsed_payload['repository'] || parsed_payload['project']
      return nil unless repository.is_a?(Hash)

      repository['id']
    end

    def parse_payload(payload)
      case payload
      when Hash
        payload
      when String
        JSON.parse(payload)
      else
        {}
      end
    rescue JSON::ParserError
      {}
    end
  end
end
