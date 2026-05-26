# frozen_string_literal: true

module RedmineDevIntegration
  class DeploymentOverviewService
    def call(project:)
      repo_ids = project.external_repositories.where(active: true).pluck(:id)
      return {} if repo_ids.empty?

      all = ExternalDeployment
        .includes(:external_repository, :issues)
        .where(external_repository_id: repo_ids)
        .order(:environment_name, completed_at: :desc, last_event_at: :desc)
        .to_a

      all.group_by(&:environment_name).transform_values(&:first)
    end
  end
end
