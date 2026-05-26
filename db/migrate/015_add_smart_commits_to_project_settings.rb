# frozen_string_literal: true

class AddSmartCommitsToProjectSettings < ActiveRecord::Migration[6.1]
  def up
    return unless table_exists?(:development_integration_project_settings)

    add_column :development_integration_project_settings, :smart_commits_enabled, :boolean, null: false, default: false unless column_exists?(:development_integration_project_settings, :smart_commits_enabled)
  end

  def down
    return unless table_exists?(:development_integration_project_settings)

    remove_column :development_integration_project_settings, :smart_commits_enabled if column_exists?(:development_integration_project_settings, :smart_commits_enabled)
  end
end
