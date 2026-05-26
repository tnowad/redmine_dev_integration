# frozen_string_literal: true

class CreateExternalRepositories < ActiveRecord::Migration[6.1]
  def up
    return if table_exists?(:external_repositories)

    create_table :external_repositories do |t|
      t.string :provider, null: false
      t.string :provider_repository_id, null: false
      t.string :owner, null: false
      t.string :repo_name, null: false
      t.string :full_name, null: false
      t.string :url, null: false
      t.references :redmine_project, null: false, index: {name: :idx_external_repositories_project_id}
      t.references :redmine_repository, null: true, index: {name: :idx_external_repositories_repository_id}
      t.boolean :active, null: false, default: true
      t.datetime :last_synced_at
      t.timestamps null: false
    end

    add_index :external_repositories,
              %i[provider provider_repository_id],
              unique: true,
              name: :idx_external_repositories_provider_repo_id
  end

  def down
    drop_table :external_repositories if table_exists?(:external_repositories)
  end
end
