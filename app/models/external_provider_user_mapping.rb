# frozen_string_literal: true

class ExternalProviderUserMapping < ApplicationRecord
  self.table_name = 'external_provider_user_mappings'

  belongs_to :user

  validates :provider, :provider_user_id, :provider_login, :user_id, presence: true
  validates :provider_user_id, uniqueness: {scope: :provider, case_sensitive: true}
  validates :provider, inclusion: {in: %w[github gitlab]}
end
