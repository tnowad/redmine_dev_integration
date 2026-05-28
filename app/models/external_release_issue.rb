# frozen_string_literal: true

class ExternalReleaseIssue < ApplicationRecord
  self.table_name = 'external_release_issues'

  belongs_to :external_release
  belongs_to :issue

  validates :external_release, :issue, presence: true
  validates :issue_id, uniqueness: {scope: :external_release_id, case_sensitive: true}
end
