# frozen_string_literal: true

class AddAutoRegisterWebhooksToProjectSettings < ActiveRecord::Migration[6.1]
  def up
    return unless table_exists?(:development_integration_project_settings)

    add_column :development_integration_project_settings, :auto_register_webhooks, :boolean, null: false, default: false unless column_exists?(:development_integration_project_settings, :auto_register_webhooks)
  end

  def down
    return unless table_exists?(:development_integration_project_settings)

    remove_column :development_integration_project_settings, :auto_register_webhooks if column_exists?(:development_integration_project_settings, :auto_register_webhooks)
  end
end
