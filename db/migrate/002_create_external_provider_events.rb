# frozen_string_literal: true

class CreateExternalProviderEvents < ActiveRecord::Migration[6.1]
  def up
    return if table_exists?(:external_provider_events)

    create_table :external_provider_events do |t|
      t.string :provider, null: false
      t.string :delivery_id, null: false
      t.string :event_type, null: false
      t.text :payload
      t.datetime :processed_at
      t.string :status, null: false
      t.text :error_message
      t.timestamps null: false
    end

    add_index :external_provider_events,
              %i[provider delivery_id event_type],
              unique: true,
              name: :idx_external_provider_events_provider_delivery_event
  end

  def down
    drop_table :external_provider_events if table_exists?(:external_provider_events)
  end
end
