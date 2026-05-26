# frozen_string_literal: true

require_relative '../test_helper'

class DevelopmentIntegrationProjectSettingTest < ActiveSupport::TestCase
  fixtures :projects, :issue_statuses

  def setup
    @project = projects(:projects_001)
    @setting = DevelopmentIntegrationProjectSetting.new(project: @project)
  end

  def test_for_project_returns_default_unsaved_setting_when_missing
    setting = DevelopmentIntegrationProjectSetting.for_project(@project)

    assert_predicate setting, :new_record?
    assert_equal @project, setting.project
    assert_equal true, setting.show_dev_panel
    assert_equal false, setting.automation_enabled
    assert_equal false, setting.pr_closed_note_enabled
    assert_equal true, setting.show_builds
    assert_equal true, setting.show_deployments
    assert_equal false, setting.build_failed_note_enabled
    assert_equal false, setting.deployment_failed_note_enabled
    assert_equal false, setting.smart_commits_enabled
    assert_nil setting.build_success_status
    assert_nil setting.deployment_staging_success_status
    assert_nil setting.deployment_production_success_status
    assert_nil setting.deployment_failed_status
  end

  def test_for_project_returns_persisted_setting_when_present
    @setting.save!

    setting = DevelopmentIntegrationProjectSetting.for_project(@project)

    assert_predicate setting, :persisted?
    assert_equal @setting.id, setting.id
  end

  def test_defaults_and_optional_mappings
    assert_predicate @setting, :valid?
    assert_equal true, @setting.show_dev_panel
    assert_equal false, @setting.automation_enabled
    assert_equal false, @setting.pr_closed_note_enabled
    assert_equal true, @setting.show_builds
    assert_equal true, @setting.show_deployments
    assert_equal false, @setting.build_failed_note_enabled
    assert_equal false, @setting.deployment_failed_note_enabled
    assert_equal false, @setting.smart_commits_enabled
    assert_nil @setting.branch_created_status
    assert_nil @setting.pr_opened_status
    assert_nil @setting.pr_merged_status
    assert_nil @setting.build_success_status
    assert_nil @setting.deployment_staging_success_status
    assert_nil @setting.deployment_production_success_status
    assert_nil @setting.deployment_failed_status

    @setting.branch_created_status = issue_statuses(:issue_statuses_001)
    @setting.pr_opened_status = issue_statuses(:issue_statuses_002)
    @setting.pr_merged_status = issue_statuses(:issue_statuses_003)
    @setting.build_success_status = issue_statuses(:issue_statuses_001)
    @setting.deployment_staging_success_status = issue_statuses(:issue_statuses_002)
    @setting.deployment_production_success_status = issue_statuses(:issue_statuses_003)
    @setting.deployment_failed_status = issue_statuses(:issue_statuses_001)

    assert_predicate @setting, :valid?
  end

  def test_requires_project
    @setting.project = nil

    assert_not_predicate @setting, :valid?
    assert @setting.errors[:project].present?
  end

  def test_rejects_duplicate_project_setting
    @setting.save!

    duplicate = DevelopmentIntegrationProjectSetting.new(project: @project)

    assert_not_predicate duplicate, :valid?
    assert_includes duplicate.errors[:project], 'has already been taken'
  end

  def test_requires_boolean_flags
    @setting.show_dev_panel = nil
    @setting.automation_enabled = nil
    @setting.pr_closed_note_enabled = nil
    @setting.show_builds = nil
    @setting.show_deployments = nil
    @setting.build_failed_note_enabled = nil
    @setting.deployment_failed_note_enabled = nil
    @setting.smart_commits_enabled = nil

    assert_not_predicate @setting, :valid?
    assert @setting.errors[:show_dev_panel].present?
    assert @setting.errors[:automation_enabled].present?
    assert @setting.errors[:pr_closed_note_enabled].present?
    assert @setting.errors[:show_builds].present?
    assert @setting.errors[:show_deployments].present?
    assert @setting.errors[:build_failed_note_enabled].present?
    assert @setting.errors[:deployment_failed_note_enabled].present?
    assert @setting.errors[:smart_commits_enabled].present?
  end
end
