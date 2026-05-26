# frozen_string_literal: true

class CreateExternalIssueLinks < ActiveRecord::Migration[6.1]
  def up
    create_external_branch_issues_table unless table_exists?(:external_branch_issues)
    create_external_pull_request_issues_table unless table_exists?(:external_pull_request_issues)
  end

  def down
    drop_table :external_pull_request_issues if table_exists?(:external_pull_request_issues)
    drop_table :external_branch_issues if table_exists?(:external_branch_issues)
  end

  private

  def create_external_branch_issues_table
    create_table :external_branch_issues do |t|
      t.references :external_branch, null: false, index: {name: :idx_external_branch_issues_branch_id}
      t.references :issue, null: false, index: {name: :idx_external_branch_issues_issue_id}
      t.timestamps null: false
    end

    add_index :external_branch_issues,
              %i[external_branch_id issue_id],
              unique: true,
              name: :idx_external_branch_issues_branch_issue
  end

  def create_external_pull_request_issues_table
    create_table :external_pull_request_issues do |t|
      t.references :external_pull_request, null: false, index: {name: :idx_external_pull_request_issues_pull_request_id}
      t.references :issue, null: false, index: {name: :idx_external_pull_request_issues_issue_id}
      t.timestamps null: false
    end

    add_index :external_pull_request_issues,
              %i[external_pull_request_id issue_id],
              unique: true,
              name: :idx_external_pull_request_issues_pull_request_issue
  end
end
