# frozen_string_literal: true

require_relative '../test_helper'

class EdgeCasesTest < Redmine::IntegrationTest
  include ActiveJob::TestHelper

  def setup
    @secret = 'topsecret'
    @project = Project.generate!
    @project.enable_module!(:redmine_dev_integration)
    Role.find(1).add_permission! :manage_development_integration
    Role.find(1).add_permission! :manage_provider_webhooks
    Role.find(1).add_permission! :trigger_provider_sync
    Setting.stubs(:plugin_redmine_dev_integration).returns({
      'github_webhook_secret' => @secret,
      'github_provider_enabled' => '1'
    })
    @original_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    clear_enqueued_jobs
  end

  def teardown
    clear_enqueued_jobs
    ActiveJob::Base.queue_adapter = @original_queue_adapter
  end

  def create_path
    "/projects/#{@project.identifier}/redmine_dev_integration"
  end

  def login_as_admin
    post '/login', params: { username: 'admin', password: 'admin' }
    assert_response :redirect
    follow_redirect!
  end

  def test_webhook_rejected_when_signature_invalid
    digest = OpenSSL::HMAC.hexdigest('SHA256', @secret, '{"action":"opened"}')
    valid_sig = "sha256=#{digest}"

    assert_difference 'ExternalProviderEvent.count', 1 do
      post '/dev_integrations/github/webhook',
           params: '{"action":"opened"}',
           headers: {
             'CONTENT_TYPE' => 'application/json',
             'X-Hub-Signature-256' => valid_sig,
             'X-Github-Delivery' => 'delivery-sig-check',
             'X-Github-Event' => 'push'
           }
    end
    assert_response :accepted

    assert_no_difference 'ExternalProviderEvent.count' do
      post '/dev_integrations/github/webhook',
           params: '{"action":"opened"}',
           headers: {
             'CONTENT_TYPE' => 'application/json',
             'X-Hub-Signature-256' => 'sha256=' + '0' * 64,
             'X-Github-Delivery' => 'delivery-bad-sig',
             'X-Github-Event' => 'push'
           }
    end
    assert_response :unauthorized
  end

  def test_webhook_rejected_when_provider_disabled
    Setting.stubs(:plugin_redmine_dev_integration).returns({
      'github_webhook_secret' => @secret,
      'github_provider_enabled' => '0'
    })

    RedmineDevIntegration::GithubWebhookSignatureVerifier.any_instance.stubs(:valid?).returns(true)

    assert_no_difference 'ExternalProviderEvent.count' do
      post '/dev_integrations/github/webhook',
           params: '{"action":"opened"}',
           headers: {
             'CONTENT_TYPE' => 'application/json',
             'X-Hub-Signature-256' => 'sha256=' + '0' * 64,
             'X-Github-Delivery' => 'delivery-disabled',
             'X-Github-Event' => 'push'
           }
    end

    assert_response :forbidden
  end

  def test_idempotent_webhook_same_delivery_id
    payload = '{"action":"opened","repository":{"id":123}}'
    digest = OpenSSL::HMAC.hexdigest('SHA256', @secret, payload)
    signature = "sha256=#{digest}"

    headers = {
      'CONTENT_TYPE' => 'application/json',
      'X-Hub-Signature-256' => signature,
      'X-Github-Delivery' => 'idempotent-delivery-id',
      'X-Github-Event' => 'push'
    }

    assert_difference 'ExternalProviderEvent.count', 1 do
      post '/dev_integrations/github/webhook', params: payload, headers: headers
    end
    assert_response :accepted

    assert_no_difference 'ExternalProviderEvent.count' do
      post '/dev_integrations/github/webhook', params: payload, headers: headers
    end
    assert_response :ok
  end

  def test_create_repository_with_invalid_data_renders_new_with_errors
    login_as_admin

    post create_path, params: {
      external_repository: {
        provider: '',
        repository_url_or_path: '',
        provider_repository_id: ''
      }
    }

    assert_response :success
    assert_select '#errorExplanation'
  end

  def test_webhook_idempotent_with_race_condition
    payload = '{"action":"opened","repository":{"id":456}}'
    digest = OpenSSL::HMAC.hexdigest('SHA256', @secret, payload)
    signature = "sha256=#{digest}"

    headers = {
      'CONTENT_TYPE' => 'application/json',
      'X-Hub-Signature-256' => signature,
      'X-Github-Delivery' => 'race-condition-delivery',
      'X-Github-Event' => 'push'
    }

    ExternalProviderEvent.create!(
      provider: 'github',
      delivery_id: 'race-condition-delivery',
      event_type: 'push',
      payload: payload,
      status: 'processed'
    )

    assert_no_difference 'ExternalProviderEvent.count' do
      post '/dev_integrations/github/webhook', params: payload, headers: headers
    end
    assert_response :ok
  end

  def test_webhook_idempotent_record_not_unique_exception
    payload = '{"action":"opened","repository":{"id":789}}'
    digest = OpenSSL::HMAC.hexdigest('SHA256', @secret, payload)
    signature = "sha256=#{digest}"

    headers = {
      'CONTENT_TYPE' => 'application/json',
      'X-Hub-Signature-256' => signature,
      'X-Github-Delivery' => 'delivery-not-unique',
      'X-Github-Event' => 'push'
    }

    assert_difference 'ExternalProviderEvent.count', 1 do
      post '/dev_integrations/github/webhook', params: payload, headers: headers
    end
    assert_response :accepted

    ExternalProviderEvent.where(delivery_id: 'delivery-not-unique').delete_all
    ExternalProviderEvent.any_instance.stubs(:save).raises(ActiveRecord::RecordNotUnique)

    assert_no_difference 'ExternalProviderEvent.count' do
      post '/dev_integrations/github/webhook', params: payload, headers: headers
    end
    assert_response :ok
  end
end
