# frozen_string_literal: true

class ExternalReview < ApplicationRecord
  self.table_name = 'external_reviews'

  belongs_to :external_pull_request

  validates :provider, :external_pull_request, :state, presence: true
  validates :provider_review_id, uniqueness: { scope: [:provider, :external_pull_request_id] }

  scope :approved, -> { where(state: 'APPROVED') }
  scope :changes_requested, -> { where(state: 'CHANGES_REQUESTED') }

  def approved?
    state == 'APPROVED'
  end

  def changes_requested?
    state == 'CHANGES_REQUESTED'
  end
end
