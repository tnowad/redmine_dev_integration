# frozen_string_literal: true

class CreateDevelopmentIntegrationAutomationRules < ActiveRecord::Migration[6.1]
  def up
    return if table_exists?(:development_integration_automation_rules)

    create_table :development_integration_automation_rules do |t|
      t.integer :project_id, null: false
      t.string :event_type, null: false
      t.string :action_type, null: false
      t.string :action_value, null: false
      t.string :environment_name, null: true
      t.boolean :active, null: false, default: true
      t.timestamps null: false
    end

    add_index :development_integration_automation_rules,
              %i[project_id active],
              name: :idx_automation_rules_project_active

    add_index :development_integration_automation_rules,
              %i[project_id event_type active],
              name: :idx_automation_rules_project_event_active

    add_index :development_integration_automation_rules,
              %i[project_id],
              name: :idx_automation_rules_project_id
  end

  def down
    drop_table :development_integration_automation_rules if table_exists?(:development_integration_automation_rules)
  end
end
