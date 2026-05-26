# frozen_string_literal: true

module RedmineDevIntegration
  class ShaIssueTracer
    def call(external_repository:, sha:)
      return [] if external_repository.blank? || sha.blank?

      ExternalPullRequest
        .where(external_repository_id: external_repository.id)
        .where(
          'source_sha = :sha OR target_sha = :sha OR merge_commit_sha = :sha',
          sha: sha.to_s
        )
        .joins(:issues)
        .distinct
        .pluck('issues.id')
    end
  end
end
