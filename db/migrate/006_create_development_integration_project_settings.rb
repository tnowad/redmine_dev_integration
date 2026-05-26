# frozen_string_literal: true

class CreateDevelopmentIntegrationProjectSettings < ActiveRecord::Migration[6.1]
  def up
    return if table_exists?(:development_integration_project_settings)

    create_table :development_integration_project_settings do |t|
      t.references :project, null: false, index: {unique: true, name: :idx_dev_integration_project_settings_project_id}
      t.boolean :show_dev_panel, null: false, default: true
      t.boolean :automation_enabled, null: false, default: false
      t.references :branch_created_status, null: true, index: {name: :idx_dev_integration_project_settings_branch_created_status_id}
      t.references :pr_opened_status, null: true, index: {name: :idx_dev_integration_project_settings_pr_opened_status_id}
      t.references :pr_merged_status, null: true, index: {name: :idx_dev_integration_project_settings_pr_merged_status_id}
      t.boolean :pr_closed_note_enabled, null: false, default: false
      t.timestamps null: false
    end
  end

  def down
    drop_table :development_integration_project_settings if table_exists?(:development_integration_project_settings)
  end
end
