# frozen_string_literal: true

class DevelopmentIntegrationEnvironmentRule < ApplicationRecord
  self.table_name = 'development_integration_environment_rules'

  belongs_to :project
  belongs_to :success_status, class_name: 'IssueStatus', optional: true
  belongs_to :failed_status, class_name: 'IssueStatus', optional: true

  validates :project_id, presence: true
  validates :environment_name, presence: true
  validates :environment_name, uniqueness: {scope: :project_id, case_sensitive: false}
  validates :active, inclusion: {in: [true, false]}
  validates :failed_note_enabled, inclusion: {in: [true, false]}

  scope :active, -> { where(active: true) }

  def self.for_project_and_environment(project, environment_name)
    return nil unless project && environment_name.present?

    active
      .where(project_id: project.id)
      .where('LOWER(environment_name) = ?', environment_name.to_s.downcase.strip)
      .first
  end
end
