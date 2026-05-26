# frozen_string_literal: true

class DevelopmentIntegrationProjectSetting < ApplicationRecord
  self.table_name = 'development_integration_project_settings'

  belongs_to :project
  belongs_to :branch_created_status, class_name: 'IssueStatus', optional: true
  belongs_to :pr_opened_status, class_name: 'IssueStatus', optional: true
  belongs_to :pr_merged_status, class_name: 'IssueStatus', optional: true
  belongs_to :build_success_status, class_name: 'IssueStatus', optional: true
  belongs_to :deployment_staging_success_status, class_name: 'IssueStatus', optional: true
  belongs_to :deployment_production_success_status, class_name: 'IssueStatus', optional: true
  belongs_to :deployment_failed_status, class_name: 'IssueStatus', optional: true

  validates :project, presence: true, uniqueness: true
  validates :show_dev_panel,
            :automation_enabled,
            :auto_register_webhooks,
            :pr_closed_note_enabled,
            :show_builds,
            :show_deployments,
            :build_failed_note_enabled,
            :deployment_failed_note_enabled,
            :smart_commits_enabled,
            inclusion: {in: [true, false]}

  after_initialize :set_default_booleans, if: :new_record?

  def self.for_project(project)
    return new(project: project) unless project

    project.development_integration_project_setting || new(project: project)
  end

  private

  def set_default_booleans
    attr = attributes.keys
    self.show_dev_panel = true if attr.include?('show_dev_panel') && show_dev_panel.nil?
    self.automation_enabled = false if attr.include?('automation_enabled') && automation_enabled.nil?
    self.auto_register_webhooks = false if attr.include?('auto_register_webhooks') && auto_register_webhooks.nil?
    self.pr_closed_note_enabled = false if attr.include?('pr_closed_note_enabled') && pr_closed_note_enabled.nil?
    self.show_builds = true if attr.include?('show_builds') && show_builds.nil?
    self.show_deployments = true if attr.include?('show_deployments') && show_deployments.nil?
    self.build_failed_note_enabled = false if attr.include?('build_failed_note_enabled') && build_failed_note_enabled.nil?
    self.deployment_failed_note_enabled = false if attr.include?('deployment_failed_note_enabled') && deployment_failed_note_enabled.nil?
    self.smart_commits_enabled = false if attr.include?('smart_commits_enabled') && smart_commits_enabled.nil?
  end
end
