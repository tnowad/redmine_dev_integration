# frozen_string_literal: true

class ExternalBuildIssue < ApplicationRecord
  self.table_name = 'external_build_issues'

  belongs_to :external_build
  belongs_to :issue

  validates :external_build, :issue, presence: true
  validates :issue_id, uniqueness: {scope: :external_build_id, case_sensitive: true}
end
