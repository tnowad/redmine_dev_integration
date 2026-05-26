# frozen_string_literal: true

require_relative '../test_helper'

class ProviderEventLoggerTest < ActiveSupport::TestCase
  fixtures :projects, :repositories

  def setup
    @logger = RedmineDevIntegration::ProviderEventLogger.new
  end

  def test_logs_expected_fields_for_known_repository
    repository = ExternalRepository.create!(
      provider: 'github',
      provider_repository_id: '123',
      owner: 'redmine',
      repo_name: 'redmine_dev_integration',
      full_name: 'redmine/redmine_dev_integration',
      url: 'https://github.com/redmine/redmine_dev_integration',
      redmine_project: projects(:projects_001),
      redmine_repository: nil
    )
    event = ExternalProviderEvent.new(
      provider: 'github',
      delivery_id: 'delivery-123',
      event_type: 'push',
      payload: JSON.generate({
        repository: {
          id: 123,
          html_url: 'https://github.com/redmine/redmine_dev_integration'
        }
      })
    )

    logged_lines = []
    fake_logger = build_fake_logger(logged_lines)

    @logger.call(event, status: 'processed', duration_ms: 42, logger: fake_logger)

    payload = logged_payload(logged_lines)
    assert_equal 'github', payload['provider']
    assert_equal 'delivery-123', payload['delivery_id']
    assert_equal 'push', payload['event_type']
    assert_equal repository.id, payload['external_repository_id']
    assert_equal 'processed', payload['status']
    assert_equal 42, payload['duration_ms']
    assert_nil payload['error_class']
    assert_nil payload['error_message']
  end

  def test_logs_error_fields_for_failure
    event = ExternalProviderEvent.new(
      provider: 'gitlab',
      delivery_id: 'delivery-456',
      event_type: 'Push Hook',
      payload: JSON.generate({
        repository: {
          id: 456,
          html_url: 'https://gitlab.example.com/redmine/redmine_dev_integration'
        }
      })
    )
    error = StandardError.new('boom')

    logged_lines = []
    fake_logger = build_fake_logger(logged_lines)

    @logger.call(event, status: 'failed', duration_ms: 7, error: error, logger: fake_logger)

    payload = logged_payload(logged_lines)
    assert_equal 'gitlab', payload['provider']
    assert_equal 'delivery-456', payload['delivery_id']
    assert_equal 'Push Hook', payload['event_type']
    assert_equal 'failed', payload['status']
    assert_equal 7, payload['duration_ms']
    assert_equal 'StandardError', payload['error_class']
    assert_equal 'boom', payload['error_message']
    assert_nil payload['external_repository_id']
  end

  def test_logger_failure_is_swallowed
    failing_logger = Object.new
    failing_logger.define_singleton_method(:info) do |_line|
      raise StandardError, 'logger boom'
    end

    event = ExternalProviderEvent.new(
      provider: 'github',
      delivery_id: 'delivery-789',
      event_type: 'push',
      payload: '{}'
    )

    assert_nil @logger.call(event, status: 'ignored', duration_ms: 1, logger: failing_logger)
  end

  private

  def build_fake_logger(logged_lines)
    Object.new.tap do |fake_logger|
      fake_logger.define_singleton_method(:info) do |line|
        logged_lines << line
      end
    end
  end

  def logged_payload(logged_lines)
    line = logged_lines.last
    JSON.parse(line.split(' ', 2).last)
  end
end
