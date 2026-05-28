# frozen_string_literal: true

class AddWebhookFieldsToExternalRepositories < ActiveRecord::Migration[6.1]
  def up
    add_column :external_repositories, :provider_webhook_id, :string, null: true unless column_exists?(:external_repositories, :provider_webhook_id)
    add_column :external_repositories, :webhook_registered_at, :timestamp, null: true unless column_exists?(:external_repositories, :webhook_registered_at)
    add_column :external_repositories, :webhook_registration_status, :string, null: false, default: 'not_registered' unless column_exists?(:external_repositories, :webhook_registration_status)
  end

  def down
    remove_column :external_repositories, :webhook_registration_status
    remove_column :external_repositories, :webhook_registered_at
    remove_column :external_repositories, :provider_webhook_id
  end
end
