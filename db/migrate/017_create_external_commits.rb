# frozen_string_literal: true

class CreateExternalCommits < ActiveRecord::Migration[6.1]
  def up
    return if table_exists?(:external_commits)

    create_table :external_commits do |t|
      t.string :provider, null: false
      t.references :external_repository, null: false, index: {name: :idx_external_commits_repository_id}
      t.string :provider_commit_id, null: false
      t.string :sha, null: false
      t.string :short_sha
      t.text :message
      t.string :author_login
      t.string :author_name
      t.string :url
      t.string :branch_name
      t.datetime :committed_at
      t.datetime :last_event_at
      t.timestamps null: false
    end

    add_index :external_commits,
              %i[provider external_repository_id provider_commit_id],
              unique: true,
              name: :idx_external_commits_provider_repository_commit_id

    add_index :external_commits,
              :sha,
              name: :idx_external_commits_sha
  end

  def down
    drop_table :external_commits if table_exists?(:external_commits)
  end
end
