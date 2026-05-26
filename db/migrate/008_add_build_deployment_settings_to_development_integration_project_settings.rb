# frozen_string_literal: true

class AddBuildDeploymentSettingsToDevelopmentIntegrationProjectSettings < ActiveRecord::Migration[6.1]
  def up
    return unless table_exists?(:development_integration_project_settings)

    add_column :development_integration_project_settings, :show_builds, :boolean, null: false, default: true unless column_exists?(:development_integration_project_settings, :show_builds)
    add_column :development_integration_project_settings, :show_deployments, :boolean, null: false, default: true unless column_exists?(:development_integration_project_settings, :show_deployments)
    add_column :development_integration_project_settings, :build_failed_note_enabled, :boolean, null: false, default: false unless column_exists?(:development_integration_project_settings, :build_failed_note_enabled)

    add_reference :development_integration_project_settings,
                  :build_success_status,
                  null: true,
                  index: {name: :idx_dev_int_proj_settings_build_success_status_id} unless column_exists?(:development_integration_project_settings, :build_success_status_id)

    add_reference :development_integration_project_settings,
                  :deployment_staging_success_status,
                  null: true,
                  index: {name: :idx_dev_int_proj_settings_dep_stg_success_status_id} unless column_exists?(:development_integration_project_settings, :deployment_staging_success_status_id)

    add_reference :development_integration_project_settings,
                  :deployment_production_success_status,
                  null: true,
                  index: {name: :idx_dev_int_proj_settings_dep_prod_success_status_id} unless column_exists?(:development_integration_project_settings, :deployment_production_success_status_id)

    add_column :development_integration_project_settings, :deployment_failed_note_enabled, :boolean, null: false, default: false unless column_exists?(:development_integration_project_settings, :deployment_failed_note_enabled)

    add_reference :development_integration_project_settings,
                  :deployment_failed_status,
                  null: true,
                  index: {name: :idx_dev_int_proj_settings_deployment_failed_status_id} unless column_exists?(:development_integration_project_settings, :deployment_failed_status_id)
  end

  def down
    return unless table_exists?(:development_integration_project_settings)

    remove_index :development_integration_project_settings, name: :idx_dev_int_proj_settings_build_success_status_id if index_exists?(:development_integration_project_settings, name: :idx_dev_int_proj_settings_build_success_status_id)
    remove_index :development_integration_project_settings, name: :idx_dev_int_proj_settings_dep_stg_success_status_id if index_exists?(:development_integration_project_settings, name: :idx_dev_int_proj_settings_dep_stg_success_status_id)
    remove_index :development_integration_project_settings, name: :idx_dev_int_proj_settings_dep_prod_success_status_id if index_exists?(:development_integration_project_settings, name: :idx_dev_int_proj_settings_dep_prod_success_status_id)
    remove_index :development_integration_project_settings, name: :idx_dev_int_proj_settings_deployment_failed_status_id if index_exists?(:development_integration_project_settings, name: :idx_dev_int_proj_settings_deployment_failed_status_id)

    remove_column :development_integration_project_settings, :build_success_status_id if column_exists?(:development_integration_project_settings, :build_success_status_id)
    remove_column :development_integration_project_settings, :deployment_staging_success_status_id if column_exists?(:development_integration_project_settings, :deployment_staging_success_status_id)
    remove_column :development_integration_project_settings, :deployment_production_success_status_id if column_exists?(:development_integration_project_settings, :deployment_production_success_status_id)
    remove_column :development_integration_project_settings, :deployment_failed_status_id if column_exists?(:development_integration_project_settings, :deployment_failed_status_id)

    remove_column :development_integration_project_settings, :show_builds if column_exists?(:development_integration_project_settings, :show_builds)
    remove_column :development_integration_project_settings, :show_deployments if column_exists?(:development_integration_project_settings, :show_deployments)
    remove_column :development_integration_project_settings, :build_failed_note_enabled if column_exists?(:development_integration_project_settings, :build_failed_note_enabled)
    remove_column :development_integration_project_settings, :deployment_failed_note_enabled if column_exists?(:development_integration_project_settings, :deployment_failed_note_enabled)
  end
end
