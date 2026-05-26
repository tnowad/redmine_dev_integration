# frozen_string_literal: true

class CreateExternalAutomationEvents < ActiveRecord::Migration[6.1]
  def up
    return if table_exists?(:external_automation_events)

    create_table :external_automation_events do |t|
      t.integer :issue_id, null: false
      t.integer :external_provider_event_id, null: true
      t.string :marker, null: false
      t.string :action_type, null: false
      t.timestamps null: false
    end

    add_index :external_automation_events,
              %i[issue_id marker],
              unique: true,
              name: :idx_external_automation_events_issue_marker

    add_index :external_automation_events,
              :external_provider_event_id,
              name: :idx_external_automation_events_provider_event_id

    add_index :external_automation_events,
              :action_type,
              name: :idx_external_automation_events_action_type
  end

  def down
    drop_table :external_automation_events if table_exists?(:external_automation_events)
  end
end
