# frozen_string_literal: true

class CreateExternalBuildsAndDeployments < ActiveRecord::Migration[6.1]
  def up
    create_external_builds_table unless table_exists?(:external_builds)
    create_external_deployments_table unless table_exists?(:external_deployments)
    create_external_build_issues_table unless table_exists?(:external_build_issues)
    create_external_deployment_issues_table unless table_exists?(:external_deployment_issues)
  end

  def down
    drop_table :external_deployment_issues if table_exists?(:external_deployment_issues)
    drop_table :external_build_issues if table_exists?(:external_build_issues)
    drop_table :external_deployments if table_exists?(:external_deployments)
    drop_table :external_builds if table_exists?(:external_builds)
  end

  private

  def create_external_builds_table
    create_table :external_builds do |t|
      t.string :provider, null: false
      t.references :external_repository, null: false, index: {name: :idx_external_builds_repository_id}
      t.string :provider_build_id, null: false
      t.integer :build_number, null: false
      t.string :name, null: false
      t.string :status, null: false
      t.string :conclusion
      t.string :url
      t.string :sha
      t.string :ref
      t.string :branch_name
      t.string :author_login
      t.datetime :started_at
      t.datetime :finished_at
      t.datetime :last_event_at
      t.timestamps null: false
    end

    add_index :external_builds,
              %i[provider external_repository_id provider_build_id],
              unique: true,
              name: :idx_external_builds_provider_repository_build_id
  end

  def create_external_deployments_table
    create_table :external_deployments do |t|
      t.string :provider, null: false
      t.references :external_repository, null: false, index: {name: :idx_external_deployments_repository_id}
      t.string :provider_deployment_id, null: false
      t.string :environment_name, null: false
      t.string :environment_url
      t.string :status, null: false
      t.string :sha
      t.string :ref
      t.string :branch_name
      t.string :description
      t.string :creator_login
      t.datetime :started_at
      t.datetime :completed_at
      t.datetime :last_event_at
      t.timestamps null: false
    end

    add_index :external_deployments,
              %i[provider external_repository_id provider_deployment_id environment_name],
              unique: true,
              name: :idx_ext_deployments_provider_repo_env
  end

  def create_external_build_issues_table
    create_table :external_build_issues do |t|
      t.references :external_build, null: false, index: {name: :idx_external_build_issues_build_id}
      t.references :issue, null: false, index: {name: :idx_external_build_issues_issue_id}
      t.timestamps null: false
    end

    add_index :external_build_issues,
              %i[external_build_id issue_id],
              unique: true,
              name: :idx_external_build_issues_build_issue
  end

  def create_external_deployment_issues_table
    create_table :external_deployment_issues do |t|
      t.references :external_deployment, null: false, index: {name: :idx_external_deployment_issues_deployment_id}
      t.references :issue, null: false, index: {name: :idx_external_deployment_issues_issue_id}
      t.timestamps null: false
    end

    add_index :external_deployment_issues,
              %i[external_deployment_id issue_id],
              unique: true,
              name: :idx_external_deployment_issues_deployment_issue
  end
end
