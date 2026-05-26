# frozen_string_literal: true

class AddWebhookFieldsToExternalRepositories < ActiveRecord::Migration[6.1]
  def up
    add_column :external_repositories, :provider_webhook_id, :string, null: true
    add_column :external_repositories, :webhook_registered_at, :timestamp, null: true
    add_column :external_repositories, :webhook_registration_status, :string, null: false, default: 'not_registered'
  end

  def down
    remove_column :external_repositories, :webhook_registration_status
    remove_column :external_repositories, :webhook_registered_at
    remove_column :external_repositories, :provider_webhook_id
  end
end
