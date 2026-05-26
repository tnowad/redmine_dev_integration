# frozen_string_literal: true

class ExternalBranch < ApplicationRecord
  self.table_name = 'external_branches'

  has_many :external_branch_issues, dependent: :delete_all
  has_many :issues, through: :external_branch_issues

  STATES = %w[active deleted].freeze

  belongs_to :external_repository

  validates :external_repository, :name, :state, presence: true
  validates :state, inclusion: {in: STATES}
  validates :name, uniqueness: {scope: :external_repository_id, case_sensitive: true}

  def active?
    state == 'active'
  end

  def deleted?
    state == 'deleted'
  end

  def soft_delete!
    return self if deleted?

    now = Time.current
    update!(state: 'deleted', deleted_at: now)
  end

  def destroy
    soft_delete!
  end

  def delete
    soft_delete!
  end

  def link_issues_from_texts(*texts)
    RedmineDevIntegration::IssueLinker.new.link(texts.flatten.compact).tap do |result|
      project_issue_ids = Issue.where(
        id: result.issue_ids.uniq,
        project_id: external_repository.redmine_project_id
      ).pluck(:id)

      project_issue_ids.each do |issue_id|
        ExternalBranchIssue.find_or_create_by!(external_branch_id: id, issue_id: issue_id)
      end
    end
  end
end
