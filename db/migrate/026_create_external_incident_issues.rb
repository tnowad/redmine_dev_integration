# frozen_string_literal: true

class CreateExternalIncidentIssues < ActiveRecord::Migration[6.1]
  def up
    return if table_exists?(:external_incident_issues)

    create_table :external_incident_issues do |t|
      t.references :external_incident, null: false
      t.references :issue, null: false
    end

    add_index :external_incident_issues, [:external_incident_id, :issue_id], unique: true, name: 'idx_ext_incident_issues_unique'
  end

  def down
    drop_table :external_incident_issues if table_exists?(:external_incident_issues)
  end
end
