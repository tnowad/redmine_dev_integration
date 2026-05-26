# frozen_string_literal: true

require_relative '../test_helper'

class ExternalProviderEventJobTest < ActiveSupport::TestCase
  def setup
    @event = ExternalProviderEvent.create!(
      provider: 'github',
      delivery_id: 'delivery-123',
      event_type: 'push',
      payload: '{"ref":"refs/heads/main"}',
      status: 'pending'
    )
  end

  def test_perform_reloads_event_and_calls_processor
    @event.update_column(:status, 'failed')

    RedmineDevIntegration::ExternalProviderEventProcessor.expects(:call).with do |event|
      assert_equal @event.id, event.id
      assert_equal 'failed', event.status
      true
    end.once

    ExternalProviderEventJob.perform_now(@event.id)
  end

  def test_perform_noops_when_event_id_is_missing
    RedmineDevIntegration::ExternalProviderEventProcessor.expects(:call).never

    ExternalProviderEventJob.perform_now(nil)
  end

  def test_perform_noops_when_event_is_deleted
    deleted_event_id = @event.id
    @event.destroy!

    RedmineDevIntegration::ExternalProviderEventProcessor.expects(:call).never

    ExternalProviderEventJob.perform_now(deleted_event_id)
  end
end
