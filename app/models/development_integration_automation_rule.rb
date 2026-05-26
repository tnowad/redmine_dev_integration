# frozen_string_literal: true

class DevelopmentIntegrationAutomationRule < ApplicationRecord
  self.table_name = 'development_integration_automation_rules'

  belongs_to :project

  VALID_ACTION_TYPES = %w[assign_user set_priority set_custom_field change_status add_note].freeze

  validates :project_id, presence: true
  validates :event_type, presence: true
  validates :action_type, presence: true, inclusion: {in: VALID_ACTION_TYPES}
  validates :action_value, presence: true
  validates :active, inclusion: {in: [true, false]}

  scope :active, -> { where(active: true) }

  def self.for_event(project, event_type, environment_name: nil)
    return none unless project && event_type.present?

    scope = active.where(project_id: project.id, event_type: event_type.to_s)
    scope = scope.where(environment_name: environment_name.to_s.strip) if environment_name.present?
    scope
  end

  def dedup_marker(issue_id)
    "auto_rule:#{id}:#{issue_id}"
  end
end
