# frozen_string_literal: true

require_relative '../test_helper'

class ExternalProviderEventTest < ActiveSupport::TestCase
  def setup
    @external_provider_event = ExternalProviderEvent.new(
      provider: 'github',
      delivery_id: 'delivery-123',
      event_type: 'push',
      payload: '{"ref":"refs/heads/main"}',
      status: 'pending'
    )
  end

  def test_valid_record
    assert_predicate @external_provider_event, :valid?
  end

  def test_requires_core_attributes
    @external_provider_event.provider = nil
    @external_provider_event.delivery_id = nil
    @external_provider_event.event_type = nil
    @external_provider_event.status = nil

    assert_not_predicate @external_provider_event, :valid?
    %i[provider delivery_id event_type status].each do |attribute|
      assert @external_provider_event.errors[attribute].present?, "expected #{attribute} to be invalid"
    end
  end

  def test_enforces_uniqueness_of_provider_delivery_id_and_event_type
    @external_provider_event.save!

    duplicate = @external_provider_event.dup
    assert_not_predicate duplicate, :valid?
    assert_includes duplicate.errors[:delivery_id], 'has already been taken'
  end

  def test_preserves_raw_payload
    payload = '{"action":"opened","nested":{"value":1}}'
    @external_provider_event.payload = payload

    assert_predicate @external_provider_event, :valid?
    @external_provider_event.save!
    assert_equal payload, @external_provider_event.reload.payload
  end

  def test_rejects_invalid_status
    @external_provider_event.status = 'queued'

    assert_not_predicate @external_provider_event, :valid?
    assert_includes @external_provider_event.errors[:status], 'is not included in the list'
  end
end
