# frozen_string_literal: true

require_relative '../test_helper'

class DevelopmentIntegrationEnvironmentRuleTest < ActiveSupport::TestCase
  fixtures :projects, :issue_statuses

  def setup
    @project = projects(:projects_001)
    @success_status = issue_statuses(:issue_statuses_001)
    @failed_status = issue_statuses(:issue_statuses_002)
  end

  def test_valid_with_required_fields
    rule = DevelopmentIntegrationEnvironmentRule.new(
      project: @project,
      environment_name: 'staging',
      success_status: @success_status,
      failed_status: @failed_status
    )

    assert_predicate rule, :valid?
  end

  def test_requires_project
    rule = DevelopmentIntegrationEnvironmentRule.new(environment_name: 'staging')
    assert_not_predicate rule, :valid?
    assert rule.errors[:project_id].present?
  end

  def test_requires_environment_name
    rule = DevelopmentIntegrationEnvironmentRule.new(project: @project)
    assert_not_predicate rule, :valid?
    assert rule.errors[:environment_name].present?
  end

  def test_rejects_duplicate_environment_name_in_same_project
    DevelopmentIntegrationEnvironmentRule.create!(project: @project, environment_name: 'staging')

    duplicate = DevelopmentIntegrationEnvironmentRule.new(project: @project, environment_name: 'staging')

    assert_not_predicate duplicate, :valid?
    assert duplicate.errors[:environment_name].present?
  end

  def test_rejects_case_insensitive_duplicate_environment_name
    DevelopmentIntegrationEnvironmentRule.create!(project: @project, environment_name: 'STAGING')

    duplicate = DevelopmentIntegrationEnvironmentRule.new(project: @project, environment_name: 'staging')

    assert_not_predicate duplicate, :valid?
  end

  def test_allows_same_environment_name_in_different_projects
    DevelopmentIntegrationEnvironmentRule.create!(project: @project, environment_name: 'staging')
    other_project = projects(:projects_002)

    rule = DevelopmentIntegrationEnvironmentRule.new(project: other_project, environment_name: 'staging')

    assert_predicate rule, :valid?
  end

  def test_requires_boolean_active_and_failed_note_enabled
    rule = DevelopmentIntegrationEnvironmentRule.new(
      project: @project,
      environment_name: 'staging',
      active: nil,
      failed_note_enabled: nil
    )

    assert_not_predicate rule, :valid?
    assert rule.errors[:active].present?
    assert rule.errors[:failed_note_enabled].present?
  end

  def test_default_values
    rule = DevelopmentIntegrationEnvironmentRule.create!(project: @project, environment_name: 'staging')

    assert_equal true, rule.active
    assert_equal false, rule.failed_note_enabled
  end

  def test_belongs_to_project
    rule = DevelopmentIntegrationEnvironmentRule.create!(project: @project, environment_name: 'staging')

    assert_equal @project, rule.project
  end

  def test_belongs_to_success_status
    rule = DevelopmentIntegrationEnvironmentRule.create!(
      project: @project,
      environment_name: 'staging',
      success_status: @success_status
    )

    assert_equal @success_status, rule.success_status
  end

  def test_belongs_to_failed_status
    rule = DevelopmentIntegrationEnvironmentRule.create!(
      project: @project,
      environment_name: 'staging',
      failed_status: @failed_status
    )

    assert_equal @failed_status, rule.failed_status
  end

  def test_for_project_and_environment_finds_exact_match
    rule = DevelopmentIntegrationEnvironmentRule.create!(
      project: @project,
      environment_name: 'production',
      success_status: @success_status
    )

    found = DevelopmentIntegrationEnvironmentRule.for_project_and_environment(@project, 'production')

    assert_equal rule.id, found.id
  end

  def test_for_project_and_environment_finds_case_insensitive
    rule = DevelopmentIntegrationEnvironmentRule.create!(
      project: @project,
      environment_name: 'Production',
      success_status: @success_status
    )

    found = DevelopmentIntegrationEnvironmentRule.for_project_and_environment(@project, 'PRODUCTION')

    assert_equal rule.id, found.id
  end

  def test_for_project_and_environment_returns_nil_when_no_match
    result = DevelopmentIntegrationEnvironmentRule.for_project_and_environment(@project, 'nonexistent')

    assert_nil result
  end

  def test_for_project_and_environment_excludes_inactive_rules
    DevelopmentIntegrationEnvironmentRule.create!(
      project: @project,
      environment_name: 'staging',
      active: false
    )

    result = DevelopmentIntegrationEnvironmentRule.for_project_and_environment(@project, 'staging')

    assert_nil result
  end
end
