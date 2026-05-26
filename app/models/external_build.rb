# frozen_string_literal: true

class ExternalBuild < ApplicationRecord
  self.table_name = 'external_builds'

  STATUSES = %w[queued in_progress success failed canceled skipped unknown].freeze

  belongs_to :external_repository
  has_many :external_build_issues, dependent: :delete_all
  has_many :issues, through: :external_build_issues

  validates :provider, :external_repository, :provider_build_id, :build_number, :name, :status, presence: true
  validates :provider_build_id, uniqueness: {scope: %i[provider external_repository_id], case_sensitive: true}
  validates :status, inclusion: {in: STATUSES}

  def link_issues_from_texts(*texts)
    RedmineDevIntegration::IssueLinker.new.link(texts.flatten.compact).tap do |result|
      project_issue_ids = Issue.where(
        id: result.issue_ids.uniq,
        project_id: external_repository.redmine_project_id
      ).pluck(:id)

      project_issue_ids.each do |issue_id|
        ExternalBuildIssue.find_or_create_by!(external_build_id: id, issue_id: issue_id)
      end
    end
  end
end
