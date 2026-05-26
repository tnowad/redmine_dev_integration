# frozen_string_literal: true

class CreateDevelopmentIntegrationEnvironmentRules < ActiveRecord::Migration[6.1]
  def up
    return if table_exists?(:development_integration_environment_rules)

    create_table :development_integration_environment_rules do |t|
      t.references :project, null: false, index: {name: :idx_env_rules_project_id}
      t.string :environment_name, null: false
      t.references :success_status, null: true, index: {name: :idx_env_rules_success_status_id}
      t.references :failed_status, null: true, index: {name: :idx_env_rules_failed_status_id}
      t.boolean :failed_note_enabled, null: false, default: false
      t.boolean :active, null: false, default: true
      t.timestamps null: false
    end

    add_index :development_integration_environment_rules,
              [:project_id, :environment_name],
              unique: true,
              name: :idx_env_rules_project_environment

    add_index :development_integration_environment_rules,
              [:project_id, :active],
              name: :idx_env_rules_project_active
  end

  def down
    drop_table :development_integration_environment_rules if table_exists?(:development_integration_environment_rules)
  end
end
