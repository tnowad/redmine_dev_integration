# frozen_string_literal: true

class AddProviderRepositoryIdToProviderEvents < ActiveRecord::Migration[6.1]
  def up
    unless column_exists?(:external_provider_events, :provider_repository_id)
      add_column :external_provider_events, :provider_repository_id, :string, null: true
    end
    add_index :external_provider_events, %i[provider provider_repository_id], name: 'idx_provider_events_repo' unless index_exists?(:external_provider_events, %i[provider provider_repository_id])
  end

  def down
    remove_index :external_provider_events, name: 'idx_provider_events_repo'
    remove_column :external_provider_events, :provider_repository_id
  end
end
