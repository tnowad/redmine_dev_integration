# frozen_string_literal: true

module RedmineDevIntegration
  class ScheduledReconciliationRunner
    def initialize(reconciliation_service_factory: nil)
      @reconciliation_service_factory = reconciliation_service_factory
    end

    def call(projects: nil, provider: nil, dry_run: false)
      lock_key = reconciliation_lock_key(projects)
      return locked_skipped_result(lock_key) unless acquire_lock(lock_key)

      repos = repositories_for(projects, provider)

      return dry_run_result(repos, provider) if dry_run

      results = repos.map { |repo| reconcile_repo(repo) }

      {
        reconciled: results.count(&:reconciled?),
        skipped: results.count(&:skipped?),
        failed: results.count(&:failed?),
        results: results
      }
    end

    private

    attr_reader :reconciliation_service_factory

    def repositories_for(projects, provider = nil)
      scope = ExternalRepository.where(active: true).includes(:redmine_project)
      scope = scope.where(redmine_project: projects) if projects.present?
      scope = scope.where(provider: provider) if provider.present?
      scope.to_a
    end

    def dry_run_result(repos, provider)
      filters = []
      filters << "provider=#{provider}" if provider.present?
      filters << "(project scoped)" if repos.size < ExternalRepository.where(active: true).count

      Rails.logger.info "[ScheduledReconciliation] DRY RUN: would reconcile #{repos.size} repositories#{filters.any? ? ' (' + filters.join(', ') + ')' : ''}"
      repos.each do |repo|
        Rails.logger.info "[ScheduledReconciliation] DRY RUN: #{repo.full_name} (#{repo.provider})"
      end

      {
        reconciled: 0,
        skipped: 0,
        failed: 0,
        dry_run: true,
        would_reconcile: repos.size,
        results: repos.map { |r| skipped_result(:dry_run, r) }
      }
    end

    def reconciliation_service
      if reconciliation_service_factory
        reconciliation_service_factory.call
      else
        ReconciliationService.new
      end
    end

    def reconcile_repo(repo)
      unless provider_enabled?(repo.provider)
        Rails.logger.info "[ScheduledReconciliation] Skipping repo #{repo.full_name} (#{repo.id}): provider #{repo.provider} is disabled"
        return skipped_result(:provider_disabled, repo)
      end

      Rails.logger.info "[ScheduledReconciliation] Reconciling repo #{repo.full_name} (#{repo.id}) via #{repo.provider}"

      result = reconciliation_service.call(
        project: repo.redmine_project,
        repository: repo,
        provider: repo.provider
      )

      if result.failed?
        Rails.logger.error "[ScheduledReconciliation] Failed repo #{repo.full_name} (#{repo.id}): #{result.reason}"
      elsif result.skipped?
        Rails.logger.info "[ScheduledReconciliation] Skipped repo #{repo.full_name} (#{repo.id}): #{result.reason}"
      else
        Rails.logger.info "[ScheduledReconciliation] Reconciled repo #{repo.full_name} (#{repo.id})"
      end

      result
    rescue StandardError => e
      Rails.logger.error "[ScheduledReconciliation] Unexpected error for repo #{repo.full_name} (#{repo.id}): #{e.message}"
      failed_result(:unexpected_error, repo)
    end

    def provider_enabled?(provider)
      setting = Setting.plugin_redmine_dev_integration
      return true unless setting.is_a?(Hash)

      key = "#{provider}_provider_enabled"
      value = if setting.key?(key)
        setting[key]
      elsif setting.key?(key.to_sym)
        setting[key.to_sym]
      end

      return true if value.nil?

      value == '1' || value == true
    end

    def skipped_result(reason, repo)
      ReconciliationService::Result.new(
        status: :skipped,
        reason: reason,
        repository: repo,
        provider: repo.provider
      )
    end

    def reconciliation_lock_key(projects)
      if projects.present? && projects.size == 1
        "reconciliation_lock:#{projects.first.id}"
      else
        "reconciliation_lock:all"
      end
    end

    def locked?(key)
      Rails.cache.exist?(key)
    end

    def acquire_lock(key)
      return false if locked?(key)

      Rails.cache.write(key, true, expires_in: 5.minutes)
      true
    end

    def locked_skipped_result(lock_key)
      Rails.logger.warn "[ScheduledReconciliation] Lock \"#{lock_key}\" is already held, skipping run"

      {
        reconciled: 0,
        skipped: 0,
        failed: 0,
        locked: true,
        lock_key: lock_key,
        results: []
      }
    end

    def failed_result(reason, repo)
      ReconciliationService::Result.new(
        status: :failed,
        reason: reason,
        repository: repo,
        provider: repo.provider
      )
    end
  end
end
