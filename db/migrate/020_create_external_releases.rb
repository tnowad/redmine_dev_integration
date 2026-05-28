# frozen_string_literal: true

class CreateExternalReleases < ActiveRecord::Migration[6.1]
  def up
    return if table_exists?(:external_releases)

    create_table :external_releases do |t|
      t.references :external_repository, null: false, foreign_key: true
      t.integer :redmine_version_id, null: true
      t.string :provider, null: false
      t.string :name, null: false
      t.string :tag_name
      t.text :body
      t.string :url
      t.string :status, null: false, default: 'published'
      t.string :author_login
      t.datetime :released_at
      t.timestamps
    end

    add_index :external_releases, [:provider, :external_repository_id, :name],
              unique: true, name: 'idx_external_releases_unique'

    add_column :external_deployments, :external_release_id, :integer unless column_exists?(:external_deployments, :external_release_id)
    add_index :external_deployments, :external_release_id unless index_exists?(:external_deployments, :external_release_id)
  end

  def down
    remove_index :external_deployments, :external_release_id if index_exists?(:external_deployments, :external_release_id)
    remove_column :external_deployments, :external_release_id if column_exists?(:external_deployments, :external_release_id)
    drop_table :external_releases if table_exists?(:external_releases)
  end
end
