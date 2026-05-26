# frozen_string_literal: true

class ExternalProviderEventJob < ApplicationJob
  queue_as :default

  def perform(event_id)
    event = ExternalProviderEvent.find_by(id: event_id)
    return if event.nil?

    RedmineDevIntegration::ExternalProviderEventProcessor.call(event)
  end
end
