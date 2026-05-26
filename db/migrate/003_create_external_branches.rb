# frozen_string_literal: true

class CreateExternalBranches < ActiveRecord::Migration[6.1]
  def up
    return if table_exists?(:external_branches)

    create_table :external_branches do |t|
      t.references :external_repository, null: false, index: {name: :idx_external_branches_repository_id}
      t.string :name, null: false
      t.string :url
      t.string :sha
      t.string :state, null: false, default: 'active'
      t.datetime :deleted_at
      t.timestamps null: false
    end

    add_index :external_branches,
              %i[external_repository_id name],
              unique: true,
              name: :idx_external_branches_repository_name
  end

  def down
    drop_table :external_branches if table_exists?(:external_branches)
  end
end
