# frozen_string_literal: true

class ExternalDeploymentIssue < ApplicationRecord
  self.table_name = 'external_deployment_issues'

  belongs_to :external_deployment
  belongs_to :issue

  validates :external_deployment, :issue, presence: true
  validates :issue_id, uniqueness: {scope: :external_deployment_id, case_sensitive: true}
end
