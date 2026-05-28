# frozen_string_literal: true

class ExternalIncident < ApplicationRecord
  self.table_name = 'external_incidents'

  belongs_to :external_repository
  belongs_to :external_deployment, optional: true
  has_many :external_incident_issues, dependent: :delete_all
  has_many :issues, through: :external_incident_issues

  validates :title, :status, :severity, presence: true

  STATUSES = %w[open investigating mitigated resolved postmortem].freeze
  SEVERITIES = %w[critical high medium low].freeze

  scope :open, -> { where(status: %w[open investigating]) }
  scope :resolved, -> { where(status: %w[mitigated resolved postmortem]) }

  def duration_hours
    return nil unless started_at && (resolved_at || mitigated_at)

    end_time = resolved_at || mitigated_at
    ((end_time - started_at) / 3600.0).round(1)
  end
end
