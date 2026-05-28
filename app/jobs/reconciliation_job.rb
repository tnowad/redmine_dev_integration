# frozen_string_literal: true

class ReconciliationJob < ApplicationJob
  queue_as :default

  def perform
    runner = RedmineDevIntegration::ScheduledReconciliationRunner.new
    runner.call
  rescue StandardError => e
    Rails.logger.warn "[DevIntegration] Auto-reconciliation job failed: #{e.message}"
  end
end
