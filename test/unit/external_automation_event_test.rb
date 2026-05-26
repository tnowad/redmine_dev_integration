# frozen_string_literal: true

require_relative '../test_helper'

class ExternalAutomationEventTest < ActiveSupport::TestCase
  def setup
    @issue = Issue.find(1)
    @external_provider_event = ExternalProviderEvent.create!(
      provider: 'github',
      delivery_id: "delivery-#{Time.now.to_i}-#{rand(100000)}",
      event_type: 'pull_request',
      payload: '{}',
      status: 'pending'
    )
    @event = ExternalAutomationEvent.new(
      issue: @issue,
      external_provider_event: @external_provider_event,
      marker: 'github:pr:7:pr_opened:1',
      action_type: 'set_pr_opened_status'
    )
  end

  def test_valid_record
    assert_predicate @event, :valid?
  end

  def test_requires_core_attributes
    @event.issue_id = nil
    @event.marker = nil
    @event.action_type = nil

    assert_not_predicate @event, :valid?
    assert @event.errors[:issue_id].present?
    assert @event.errors[:marker].present?
    assert @event.errors[:action_type].present?
  end

  def test_enforces_uniqueness_of_issue_and_marker
    @event.save!

    duplicate = @event.dup
    assert_not_predicate duplicate, :valid?
    assert_includes duplicate.errors[:marker], 'has already been taken'
  end

  def test_persists_external_provider_event_id_when_present
    @event.save!

    assert_equal @external_provider_event.id, @event.reload.external_provider_event_id
  end

  def test_accepts_action_type_values
    @event.action_type = 'set_deployment_failed_outcome'

    assert_predicate @event, :valid?
  end
end
