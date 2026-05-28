# frozen_string_literal: true

class CreateExternalIncidents < ActiveRecord::Migration[6.1]
  def up
    return if table_exists?(:external_incidents)

    create_table :external_incidents do |t|
      t.references :external_repository, null: false
      t.references :external_deployment, null: true
      t.integer :redmine_issue_id, null: true
      t.string :title, null: false
      t.string :status, null: false, default: 'open'
      t.string :severity, null: false, default: 'medium'
      t.string :affected_service
      t.datetime :started_at
      t.datetime :mitigated_at
      t.datetime :resolved_at
      t.timestamps
    end

    add_index :external_incidents, :status
    add_index :external_incidents, [:external_repository_id, :status]
  end

  def down
    drop_table :external_incidents if table_exists?(:external_incidents)
  end
end
