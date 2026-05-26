# frozen_string_literal: true

class ExternalProviderEvent < ApplicationRecord
  STATUSES = %w[pending processed failed ignored].freeze

  validates :provider, :delivery_id, :event_type, :status, presence: true
  validates :delivery_id, uniqueness: {scope: %i[provider event_type], case_sensitive: true}
  validates :status, inclusion: {in: STATUSES}
end
