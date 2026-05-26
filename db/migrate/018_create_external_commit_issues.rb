# frozen_string_literal: true

class CreateExternalCommitIssues < ActiveRecord::Migration[6.1]
  def up
    return if table_exists?(:external_commit_issues)

    create_table :external_commit_issues do |t|
      t.references :external_commit, null: false, index: {name: :idx_external_commit_issues_commit_id}
      t.references :issue, null: false, index: {name: :idx_external_commit_issues_issue_id}
      t.timestamps null: false
    end

    add_index :external_commit_issues,
              %i[external_commit_id issue_id],
              unique: true,
              name: :idx_external_commit_issues_commit_issue
  end

  def down
    drop_table :external_commit_issues if table_exists?(:external_commit_issues)
  end
end
