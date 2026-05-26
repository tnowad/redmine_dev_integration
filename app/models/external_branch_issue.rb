# frozen_string_literal: true

class ExternalBranchIssue < ApplicationRecord
  self.table_name = 'external_branch_issues'

  belongs_to :external_branch
  belongs_to :issue

  validates :external_branch, :issue, presence: true
  validates :issue_id, uniqueness: {scope: :external_branch_id, case_sensitive: true}
end
