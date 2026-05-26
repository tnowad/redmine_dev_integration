# frozen_string_literal: true

class ExternalCommit < ApplicationRecord
  self.table_name = 'external_commits'

  belongs_to :external_repository
  has_many :external_commit_issues, dependent: :delete_all
  has_many :issues, through: :external_commit_issues

  validates :provider, :external_repository, :provider_commit_id, :sha, :message, presence: true
  validates :provider_commit_id, uniqueness: {scope: %i[provider external_repository_id], case_sensitive: true}

  def link_issues_from_texts(*texts)
    RedmineDevIntegration::IssueLinker.new.link(texts.flatten.compact).tap do |result|
      project_issue_ids = Issue.where(
        id: result.issue_ids.uniq,
        project_id: external_repository.redmine_project_id
      ).pluck(:id)

      project_issue_ids.each do |issue_id|
        ExternalCommitIssue.find_or_create_by!(external_commit_id: id, issue_id: issue_id)
      end
    end
  end
end
