# frozen_string_literal: true

require_relative '../../test_helper'

class DevIntegrations::GitlabWebhooksControllerTest < Redmine::IntegrationTest
  include ActiveJob::TestHelper

  def setup
    @token = 'topsecret'
    Setting.stubs(:plugin_redmine_dev_integration).returns({
      'gitlab_webhook_token' => @token,
      'gitlab_provider_enabled' => '1'
    })
    @payload = '{"object_kind":"push"}'
    @delivery_id = 'idempotency-123'
    @event_type = 'Push Hook'
    @original_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    clear_enqueued_jobs
  end

  def teardown
    clear_enqueued_jobs
    ActiveJob::Base.queue_adapter = @original_queue_adapter
  end

  def test_rejects_invalid_token
    assert_no_difference 'ExternalProviderEvent.count' do
      post webhook_path, headers: webhook_headers(token: 'wrong-token')
    end

    assert_response :unauthorized
  end

  def test_rejects_missing_token
    headers = webhook_headers(token: nil)
    headers.delete('X-Gitlab-Token')

    assert_no_difference 'ExternalProviderEvent.count' do
      post webhook_path, headers: headers
    end

    assert_response :unauthorized
  end

  def test_stores_valid_event
    RedmineDevIntegration::ExternalProviderEventProcessor.expects(:call).never

    assert_difference 'ExternalProviderEvent.count', 1 do
      assert_enqueued_jobs 1 do
        post webhook_path, headers: webhook_headers(token: @token)
      end
    end

    assert_response :accepted

    event = ExternalProviderEvent.last
    assert_equal 'gitlab', event.provider
    assert_equal @delivery_id, event.delivery_id
    assert_equal @event_type, event.event_type
    assert_equal @payload, event.payload
    assert_equal 'pending', event.status
    assert_equal ExternalProviderEventJob, enqueued_jobs.last[:job]
    assert_equal [event.id], enqueued_jobs.last[:args]
  end

  def test_ignores_duplicate_event
    ExternalProviderEvent.create!(
      provider: 'gitlab',
      delivery_id: @delivery_id,
      event_type: @event_type,
      payload: @payload,
      status: 'pending'
    )

    RedmineDevIntegration::ExternalProviderEventProcessor.expects(:call).never

    assert_no_difference 'ExternalProviderEvent.count' do
      assert_no_enqueued_jobs do
        post webhook_path, headers: webhook_headers(token: @token)
      end
    end

    assert_response :ok
  end

  def test_returns_ok_when_save_raises_record_not_unique
    ExternalProviderEvent.any_instance.stubs(:save).raises(ActiveRecord::RecordNotUnique)
    RedmineDevIntegration::ExternalProviderEventProcessor.expects(:call).never

    assert_no_difference 'ExternalProviderEvent.count' do
      post webhook_path, headers: webhook_headers(token: @token)
    end

    assert_response :ok
  end

  def test_rejects_when_provider_disabled
    Setting.stubs(:plugin_redmine_dev_integration).returns({
      'gitlab_webhook_token' => @token,
      'gitlab_provider_enabled' => '0'
    })

    RedmineDevIntegration::ExternalProviderEventProcessor.expects(:call).never

    assert_no_difference 'ExternalProviderEvent.count' do
      post webhook_path, headers: webhook_headers(token: @token)
    end

    assert_response :forbidden
  end

  def test_provider_defaults_to_enabled_when_setting_is_missing
    Setting.stubs(:plugin_redmine_dev_integration).returns({'gitlab_webhook_token' => @token})
    RedmineDevIntegration::ExternalProviderEventProcessor.expects(:call).never

    assert_difference 'ExternalProviderEvent.count', 1 do
      assert_enqueued_jobs 1 do
        post webhook_path, headers: webhook_headers(token: @token)
      end
    end

    assert_response :accepted
  end

  private

  def webhook_path
    '/dev_integrations/gitlab/webhook'
  end

  def webhook_headers(token:)
    {
      'RAW_POST_DATA' => @payload,
      'CONTENT_TYPE' => 'application/json',
      'Idempotency-Key' => @delivery_id,
      'X-Gitlab-Event' => @event_type
    }.tap do |headers|
      headers['X-Gitlab-Token'] = token if token.present?
    end
  end
end
