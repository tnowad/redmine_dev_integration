# frozen_string_literal: true

class ExternalAutomationEvent < ApplicationRecord
  belongs_to :issue
  belongs_to :external_provider_event, optional: true

  validates :issue_id, presence: true
  validates :marker, presence: true
  validates :action_type, presence: true
  validates :marker, uniqueness: {scope: :issue_id, case_sensitive: true}
end
