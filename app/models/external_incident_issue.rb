# frozen_string_literal: true

class ExternalIncidentIssue < ApplicationRecord
  self.table_name = 'external_incident_issues'

  belongs_to :external_incident
  belongs_to :issue

  validates :external_incident, :issue, presence: true
  validates :issue_id, uniqueness: {scope: :external_incident_id, case_sensitive: true}
end
