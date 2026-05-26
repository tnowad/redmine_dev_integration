# frozen_string_literal: true

require_relative '../../test_helper'

class DevIntegrations::GitHubWebhooksControllerTest < Redmine::IntegrationTest
  include ActiveJob::TestHelper

  def setup
    @secret = 'topsecret'
    Setting.stubs(:plugin_redmine_dev_integration).returns({
      'github_webhook_secret' => @secret,
      'github_provider_enabled' => '1'
    })
    @payload = '{"action":"opened"}'
    @delivery_id = 'delivery-123'
    @event_type = 'push'
    @original_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    clear_enqueued_jobs
  end

  def teardown
    clear_enqueued_jobs
    ActiveJob::Base.queue_adapter = @original_queue_adapter
  end

  def test_rejects_invalid_signature
    assert_no_difference 'ExternalProviderEvent.count' do
      post webhook_path, headers: webhook_headers(signature: 'sha256=' + '0' * 64)
    end

    assert_response :unauthorized
  end

  def test_stores_valid_event
    RedmineDevIntegration::ExternalProviderEventProcessor.expects(:call).never

    assert_difference 'ExternalProviderEvent.count', 1 do
      assert_enqueued_jobs 1 do
        post webhook_path, headers: webhook_headers(signature: valid_signature)
      end
    end

    assert_response :accepted

    event = ExternalProviderEvent.last
    assert_equal 'github', event.provider
    assert_equal @delivery_id, event.delivery_id
    assert_equal @event_type, event.event_type
    assert_equal @payload, event.payload
    assert_equal 'pending', event.status
    assert_equal ExternalProviderEventJob, enqueued_jobs.last[:job]
    assert_equal [event.id], enqueued_jobs.last[:args]
  end

  def test_ignores_duplicate_event
    ExternalProviderEvent.create!(
      provider: 'github',
      delivery_id: @delivery_id,
      event_type: @event_type,
      payload: @payload,
      status: 'pending'
    )

    RedmineDevIntegration::ExternalProviderEventProcessor.expects(:call).never

    assert_no_difference 'ExternalProviderEvent.count' do
      assert_no_enqueued_jobs do
        post webhook_path, headers: webhook_headers(signature: valid_signature)
      end
    end

    assert_response :ok
  end

  def test_returns_ok_when_save_raises_record_not_unique
    ExternalProviderEvent.any_instance.stubs(:save).raises(ActiveRecord::RecordNotUnique)
    RedmineDevIntegration::ExternalProviderEventProcessor.expects(:call).never

    assert_no_difference 'ExternalProviderEvent.count' do
      post webhook_path, headers: webhook_headers(signature: valid_signature)
    end

    assert_response :ok
  end

  def test_rejects_when_provider_disabled
    Setting.stubs(:plugin_redmine_dev_integration).returns({
      'github_webhook_secret' => @secret,
      'github_provider_enabled' => '0'
    })

    RedmineDevIntegration::ExternalProviderEventProcessor.expects(:call).never

    assert_no_difference 'ExternalProviderEvent.count' do
      post webhook_path, headers: webhook_headers(signature: valid_signature)
    end

    assert_response :forbidden
  end

  def test_provider_defaults_to_enabled_when_setting_is_missing
    Setting.stubs(:plugin_redmine_dev_integration).returns({'github_webhook_secret' => @secret})
    RedmineDevIntegration::ExternalProviderEventProcessor.expects(:call).never

    assert_difference 'ExternalProviderEvent.count', 1 do
      assert_enqueued_jobs 1 do
        post webhook_path, headers: webhook_headers(signature: valid_signature)
      end
    end

    assert_response :accepted
  end

  def test_stores_create_event_type
    @event_type = 'create'
    @payload = JSON.generate({
      ref: 'feature/RAK-1-login',
      ref_type: 'branch',
      repository: {id: 123, html_url: 'https://github.com/redmine/redmine_dev_integration'}
    })

    assert_difference 'ExternalProviderEvent.count', 1 do
      assert_enqueued_jobs 1 do
        post webhook_path, headers: webhook_headers(signature: valid_signature)
      end
    end

    assert_response :accepted
    assert_equal 'create', ExternalProviderEvent.last.event_type
  end

  private

  def webhook_path
    '/dev_integrations/github/webhook'
  end

  def webhook_headers(signature:)
    {
      'RAW_POST_DATA' => @payload,
      'CONTENT_TYPE' => 'application/json',
      'X-Hub-Signature-256' => signature,
      'X-GitHub-Delivery' => @delivery_id,
      'X-GitHub-Event' => @event_type
    }
  end

  def valid_signature
    digest = OpenSSL::HMAC.hexdigest('SHA256', @secret, @payload)
    "sha256=#{digest}"
  end
end
