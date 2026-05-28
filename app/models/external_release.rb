# frozen_string_literal: true

class ExternalRelease < ApplicationRecord
  self.table_name = 'external_releases'

  belongs_to :external_repository
  belongs_to :redmine_version, class_name: 'Version', optional: true
  has_many :external_deployments
  has_many :external_release_issues, dependent: :delete_all
  has_many :issues, through: :external_release_issues

  validates :provider, :external_repository, :name, :status, presence: true
  validates :name, uniqueness: {scope: [:provider, :external_repository_id]}

  scope :published, -> { where(status: 'published') }

  def link_issues_from_deployments
    deployment_issue_ids = ExternalDeploymentIssue
      .joins(:external_deployment)
      .where(external_deployments: {external_release_id: id})
      .pluck(:issue_id)
      .uniq

    deployment_issue_ids.each do |issue_id|
      ExternalReleaseIssue.find_or_create_by!(external_release_id: id, issue_id: issue_id)
    end
  end
end
