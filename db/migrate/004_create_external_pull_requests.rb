# frozen_string_literal: true

class CreateExternalPullRequests < ActiveRecord::Migration[6.1]
  def up
    return if table_exists?(:external_pull_requests)

    create_table :external_pull_requests do |t|
      t.string :provider, null: false
      t.references :external_repository,
                   null: false,
                   index: {name: :idx_external_pull_requests_repository_id}
      t.integer :number, null: false
      t.string :title, null: false
      t.text :body
      t.string :url, null: false
      t.string :state, null: false
      t.string :author_login
      t.string :source_branch
      t.string :target_branch
      t.boolean :merged, null: false, default: false
      t.datetime :merged_at
      t.datetime :opened_at
      t.datetime :closed_at
      t.datetime :last_event_at
      t.timestamps null: false
    end

    add_index :external_pull_requests,
              %i[provider external_repository_id number],
              unique: true,
              name: :idx_external_pull_requests_provider_repository_number
  end

  def down
    drop_table :external_pull_requests if table_exists?(:external_pull_requests)
  end
end
