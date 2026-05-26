# frozen_string_literal: true

class ExternalPullRequestIssue < ApplicationRecord
  self.table_name = 'external_pull_request_issues'

  belongs_to :external_pull_request
  belongs_to :issue

  validates :external_pull_request, :issue, presence: true
  validates :issue_id, uniqueness: {scope: :external_pull_request_id, case_sensitive: true}
end
