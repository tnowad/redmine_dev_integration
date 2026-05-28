# frozen_string_literal: true

module RedmineDevIntegration
  class MetricsService
    Result = Struct.new(:deployment_frequency, :lead_time_hours, :change_failure_rate,
                        :mttr_hours, :deployments_count, :failures_count,
                        :success_count, :trend_data, :env_breakdown, :dora_band,
                        :trend_comparison, keyword_init: true)

    def call(project:, range: 30.days)
      @range = range
      repo_ids = project.external_repositories.active.pluck(:id)
      return empty_result if repo_ids.empty?

      since = range.ago
      deployments = ExternalDeployment
        .where(external_repository_id: repo_ids)
        .where(completed_at: since..Time.current)
        .where(status: %w[success failed])

      success = deployments.select { |d| d.status == 'success' && !d.rollback? }
      failed = deployments.select { |d| d.status == 'failed' || d.rollback? }
      total = success.size + failed.size
      days = (range / 1.day).to_f

      df = total > 0 ? (total.to_f / days).round(2) : 0

      lt = compute_lead_time(project, repo_ids, since)

      failed_deploy_ids = ExternalIncident.where(external_repository_id: repo_ids).where.not(external_deployment_id: nil).pluck(:external_deployment_id).uniq
      fail_count = deployments.count { |d| d.status == 'failed' || d.rollback? || failed_deploy_ids.include?(d.id) }
      cfr = total > 0 ? ((fail_count.to_f / total) * 100).round(1) : 0

      mttr = compute_mttr(repo_ids, since)

      trend = compute_trend(deployments, range)

      env_bd = deployments.group_by(&:environment_name).map do |env, deploys|
        s = deploys.count { |d| d.status == 'success' && !d.rollback? }
        f = deploys.count { |d| d.status == 'failed' || d.rollback? }
        { environment: env, deployments: deploys.size, successes: s, failures: f,
          failure_rate: deploys.size > 0 ? ((f.to_f / deploys.size) * 100).round(1) : 0 }
      end

      band = dora_band(df, lt, cfr, mttr, total)

      current = Result.new(
        deployment_frequency: df,
        lead_time_hours: lt,
        change_failure_rate: cfr,
        mttr_hours: mttr,
        deployments_count: total,
        failures_count: fail_count,
        success_count: success.size,
        trend_data: trend,
        env_breakdown: env_bd,
        dora_band: band
      )

      tc = compute_trend_comparison(repo_ids, current)

      Result.new(
        deployment_frequency: df,
        lead_time_hours: lt,
        change_failure_rate: cfr,
        mttr_hours: mttr,
        deployments_count: total,
        failures_count: fail_count,
        success_count: success.size,
        trend_data: trend,
        env_breakdown: env_bd,
        dora_band: band,
        trend_comparison: tc
      )
    end

    private

    def compute_lead_time(_project, repo_ids, since)
      times = lead_times_from_commits(repo_ids, since)
      return (times.sum / times.size).round(1) if times.any?

      lead_times_from_prs(repo_ids, since)
    end

  def lead_times_from_commits(repo_ids, since)
    deployments = ExternalDeployment.where(external_repository_id: repo_ids, status: 'success')
      .where(completed_at: since..)
      .where.not(sha: nil)
    return [] if deployments.empty?

    shas = deployments.pluck(:sha).uniq
    commits_by_sha = ExternalCommit.where(external_repository_id: repo_ids, sha: shas)
      .where.not(committed_at: nil)
      .index_by(&:sha)

    deployments.filter_map do |deploy|
      commit = commits_by_sha[deploy.sha]
      next unless commit&.committed_at && deploy.completed_at
      hours = ((deploy.completed_at - commit.committed_at) / 3600.0).round(1)
      hours if hours >= 0
    end
  end

  def lead_times_from_prs(repo_ids, since)
      prs = ExternalPullRequest
        .where(external_repository_id: repo_ids)
        .where(merged: true)
        .where(merged_at: since..)
      return 0 if prs.empty?

      avg = prs.sum { |pr|
        pr.opened_at && pr.merged_at ? ((pr.merged_at - pr.opened_at) / 3600.0).round(1) : 0
      }.to_f / prs.size
      avg.round(1)
    end

    def compute_mttr(repo_ids, since)
      incidents = ExternalIncident
        .where(external_repository_id: repo_ids)
        .where(status: %w[mitigated resolved])
        .where.not(resolved_at: nil)
        .where.not(started_at: nil)
        .where(resolved_at: since..)
      return 0 if incidents.empty?

      hours = incidents.map(&:duration_hours).compact
      return 0 if hours.empty?
      (hours.sum / hours.size).round(1)
    end

    def compute_trend(deployments, range)
      days_ago = range / 1.day
      (0...days_ago).map do |d|
        date = (days_ago - d).days.ago.to_date
        count = deployments.count { |dep| dep.completed_at&.to_date == date && dep.status == 'success' && !dep.rollback? }
        { date: date.to_s, count: count }
      end
    end

    def dora_band(df, lt, cfr, mttr, total)
      return nil if total == 0

      scores = 0
      scores += 1 if df >= 1
      scores += 1 if lt.between?(0, 1)
      scores += 1 if cfr <= 5
      scores += 1 if mttr.between?(0, 1)

      case scores
      when 4 then 'elite'
      when 3 then 'high'
      when 2 then 'medium'
      else 'low'
      end
    end

    def compute_trend_comparison(repo_ids, current)
      prev_since = (@range * 2).ago
      prev_until = @range.ago
      days = (@range / 1.day).to_f

      prev_deployments = ExternalDeployment
        .where(external_repository_id: repo_ids)
        .where(completed_at: prev_since..prev_until)
        .where(status: %w[success failed])

      prev_failed = prev_deployments.select { |d| d.status == 'failed' || d.rollback? }.size
      prev_total = prev_deployments.size

      return {} if prev_total == 0

      prev_df = (prev_total.to_f / days).round(2)
      prev_cfr = (prev_failed.to_f / prev_total * 100).round(1)

      prev_prs = ExternalPullRequest
        .where(external_repository_id: repo_ids)
        .where(merged: true)
        .where(merged_at: prev_since..prev_until)

      prev_lt = if prev_prs.any?
        (prev_prs.sum { |pr|
          next 0 unless pr.opened_at && pr.merged_at
          ((pr.merged_at - pr.opened_at) / 3600.0).round(1)
        }.to_f / prev_prs.size).round(1)
      else
        0
      end

      prev_mttr = compute_mttr(repo_ids, prev_since)

      {
        deployment_frequency: compare_higher_better(current.deployment_frequency, prev_df),
        lead_time_hours: compare_lower_better(current.lead_time_hours, prev_lt),
        change_failure_rate: compare_lower_better(current.change_failure_rate, prev_cfr),
        mttr_hours: compare_lower_better(current.mttr_hours, prev_mttr)
      }.compact
    end

    def compare_higher_better(current, previous)
      return nil if previous.nil? || previous.zero?
      percent = ((current - previous).abs.fdiv(previous) * 100).round
      no_change = current == previous
      { arrow: arrow_for(!no_change && current > previous, no_change), percent: percent, improved: !no_change && current > previous }
    end

    def compare_lower_better(current, previous)
      return nil if previous.nil? || previous.zero?
      percent = ((current - previous).abs.fdiv(previous) * 100).round
      no_change = current == previous
      { arrow: arrow_for(!no_change && current < previous, no_change), percent: percent, improved: !no_change && current < previous }
    end

    def arrow_for(improved, no_change)
      return '→' if no_change
      improved ? '↑' : '↓'
    end

    def empty_result
      Result.new(deployment_frequency: 0, lead_time_hours: 0, change_failure_rate: 0,
                 mttr_hours: 0, deployments_count: 0, failures_count: 0,
                 success_count: 0, trend_data: [], env_breakdown: [], dora_band: nil,
                 trend_comparison: {})
    end
  end
end
