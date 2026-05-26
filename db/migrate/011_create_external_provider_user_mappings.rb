# frozen_string_literal: true

class CreateExternalProviderUserMappings < ActiveRecord::Migration[6.1]
  def up
    create_external_provider_user_mappings_table unless table_exists?(:external_provider_user_mappings)
  end

  def down
    drop_table :external_provider_user_mappings if table_exists?(:external_provider_user_mappings)
  end

  private

  def create_external_provider_user_mappings_table
    create_table :external_provider_user_mappings do |t|
      t.string :provider, null: false
      t.string :provider_user_id, null: false
      t.string :provider_login, null: false
      t.references :user, null: false, index: {name: :idx_external_provider_user_mappings_user_id}, foreign_key: true
      t.timestamps null: false
    end

    add_index :external_provider_user_mappings,
              %i[provider provider_user_id],
              unique: true,
              name: :idx_external_provider_user_mappings_provider_uid

    add_index :external_provider_user_mappings,
              %i[provider provider_login],
              name: :idx_external_provider_user_mappings_provider_login
  end
end
