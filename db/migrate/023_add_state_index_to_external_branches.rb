class AddStateIndexToExternalBranches < ActiveRecord::Migration[6.1]
  def up
    unless index_exists?(:external_branches, :state, name: 'idx_external_branches_state')
      add_index :external_branches, :state, name: 'idx_external_branches_state'
    end
  end

  def down
    remove_index :external_branches, name: 'idx_external_branches_state'
  end
end
