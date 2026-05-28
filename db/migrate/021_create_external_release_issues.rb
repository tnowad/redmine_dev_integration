# frozen_string_literal: true

class CreateExternalReleaseIssues < ActiveRecord::Migration[6.1]
  def up
    return if table_exists?(:external_release_issues)

    create_table :external_release_issues do |t|
      t.references :external_release, null: false
      t.references :issue, null: false
    end

    add_index :external_release_issues, [:external_release_id, :issue_id], unique: true, name: 'idx_ext_release_issues_unique'
  end

  def down
    drop_table :external_release_issues if table_exists?(:external_release_issues)
  end
end
