# frozen_string_literal: true

class ExternalCommitIssue < ApplicationRecord
  self.table_name = 'external_commit_issues'

  belongs_to :external_commit
  belongs_to :issue

  validates :external_commit, :issue, presence: true
  validates :issue_id, uniqueness: {scope: :external_commit_id, case_sensitive: true}
end
