class AddRollbackToDeployments < ActiveRecord::Migration[6.1]
  def up
    unless column_exists?(:external_deployments, :rollback)
      add_column :external_deployments, :rollback, :boolean, default: false, null: false
    end
    unless column_exists?(:external_deployments, :rolled_back_from_sha)
      add_column :external_deployments, :rolled_back_from_sha, :string, null: true
    end
  end

  def down
    remove_column :external_deployments, :rollback if column_exists?(:external_deployments, :rollback)
    remove_column :external_deployments, :rolled_back_from_sha if column_exists?(:external_deployments, :rolled_back_from_sha)
  end
end
