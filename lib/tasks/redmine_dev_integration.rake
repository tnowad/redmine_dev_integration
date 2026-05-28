# frozen_string_literal: true

namespace :redmine_dev_integration do
  desc 'Reconcile all active external repositories (set PROVIDER=github|gitlab|bitbucket to filter, DRY_RUN=1 to preview only)'
  task reconcile_all: :environment do
    require_relative '../redmine_dev_integration/scheduled_reconciliation_runner'
    require_relative '../redmine_dev_integration/reconciliation_service'

    provider = ENV['PROVIDER'].presence
    dry_run = ENV['DRY_RUN'].present? && ENV['DRY_RUN'] != '0' && ENV['DRY_RUN'] != 'false'

    runner = RedmineDevIntegration::ScheduledReconciliationRunner.new
    summary = runner.call(provider: provider, dry_run: dry_run)

    if dry_run
      puts "DRY RUN: would reconcile #{summary[:would_reconcile]} repositories"
    else
      puts "#{summary[:reconciled]} reconciled, #{summary[:skipped]} skipped, #{summary[:failed]} failed"
    end
  end

  desc 'Reconcile external repositories for a specific project (set PROJECT=identifier, PROVIDER=github|gitlab|bitbucket, DRY_RUN=1)'
  task reconcile_project: :environment do
    require_relative '../redmine_dev_integration/scheduled_reconciliation_runner'
    require_relative '../redmine_dev_integration/reconciliation_service'

    identifier = ENV['PROJECT']
    abort 'Please set PROJECT=identifier' if identifier.blank?

    project = Project.find_by(identifier: identifier)
    abort "Project with identifier '#{identifier}' not found" unless project

    provider = ENV['PROVIDER'].presence
    dry_run = ENV['DRY_RUN'].present? && ENV['DRY_RUN'] != '0' && ENV['DRY_RUN'] != 'false'

    runner = RedmineDevIntegration::ScheduledReconciliationRunner.new
    summary = runner.call(projects: [project], provider: provider, dry_run: dry_run)

    if dry_run
      puts "DRY RUN: would reconcile #{summary[:would_reconcile]} repositories"
    else
      puts "#{summary[:reconciled]} reconciled, #{summary[:skipped]} skipped, #{summary[:failed]} failed"
    end
  end

  desc 'Clear payloads for old processed/ignored provider events (default: > 90 days)'
  task archive_events: :environment do
    days = (ENV['DAYS'] || 90).to_i
    cutoff = days.days.ago

    count = ExternalProviderEvent.where('created_at < ?', cutoff)
      .where(status: %w[processed ignored])
      .update_all(payload: nil)

    puts "Cleared payloads for #{count} events older than #{days} days"
  end
end
