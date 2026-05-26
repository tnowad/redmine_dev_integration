# frozen_string_literal: true

class AddShaFieldsToExternalPullRequests < ActiveRecord::Migration[6.1]
  def up
    add_column :external_pull_requests, :source_sha, :string unless column_exists?(:external_pull_requests, :source_sha)
    add_column :external_pull_requests, :target_sha, :string unless column_exists?(:external_pull_requests, :target_sha)
    add_column :external_pull_requests, :merge_commit_sha, :string unless column_exists?(:external_pull_requests, :merge_commit_sha)
  end

  def down
    remove_column :external_pull_requests, :merge_commit_sha if column_exists?(:external_pull_requests, :merge_commit_sha)
    remove_column :external_pull_requests, :target_sha if column_exists?(:external_pull_requests, :target_sha)
    remove_column :external_pull_requests, :source_sha if column_exists?(:external_pull_requests, :source_sha)
  end
end
