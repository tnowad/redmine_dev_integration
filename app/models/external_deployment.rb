# frozen_string_literal: true

class ExternalDeployment < ApplicationRecord
  self.table_name = 'external_deployments'

  STATUSES = %w[pending in_progress success failed canceled rolled_back unknown].freeze

  belongs_to :external_repository
  has_many :external_deployment_issues, dependent: :delete_all
  has_many :issues, through: :external_deployment_issues

  validates :provider, :external_repository, :provider_deployment_id, :environment_name, :status, presence: true
  validates :provider_deployment_id,
            uniqueness: {scope: %i[provider external_repository_id environment_name], case_sensitive: true}
  validates :status, inclusion: {in: STATUSES}

  def link_issues_from_texts(*texts)
    RedmineDevIntegration::IssueLinker.new.link(texts.flatten.compact).tap do |result|
      project_issue_ids = Issue.where(
        id: result.issue_ids.uniq,
        project_id: external_repository.redmine_project_id
      ).pluck(:id)

      project_issue_ids.each do |issue_id|
        ExternalDeploymentIssue.find_or_create_by!(external_deployment_id: id, issue_id: issue_id)
      end
    end
  end
end
