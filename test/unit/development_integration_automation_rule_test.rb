# frozen_string_literal: true

require_relative '../test_helper'

class DevelopmentIntegrationAutomationRuleTest < ActiveSupport::TestCase
  fixtures :projects, :issue_statuses

  def setup
    @project = projects(:projects_001)
  end

  def test_valid_with_required_fields
    rule = DevelopmentIntegrationAutomationRule.new(
      project: @project,
      event_type: 'pr_opened',
      action_type: 'assign_user',
      action_value: 'developer1'
    )

    assert_predicate rule, :valid?
  end

  def test_requires_project
    rule = DevelopmentIntegrationAutomationRule.new(
      event_type: 'pr_opened',
      action_type: 'assign_user',
      action_value: 'developer1'
    )
    assert_not_predicate rule, :valid?
    assert rule.errors[:project_id].present?
  end

  def test_requires_event_type
    rule = DevelopmentIntegrationAutomationRule.new(
      project: @project,
      action_type: 'assign_user',
      action_value: 'developer1'
    )
    assert_not_predicate rule, :valid?
    assert rule.errors[:event_type].present?
  end

  def test_requires_action_type
    rule = DevelopmentIntegrationAutomationRule.new(
      project: @project,
      event_type: 'pr_opened',
      action_value: 'developer1'
    )
    assert_not_predicate rule, :valid?
    assert rule.errors[:action_type].present?
  end

  def test_requires_action_value
    rule = DevelopmentIntegrationAutomationRule.new(
      project: @project,
      event_type: 'pr_opened',
      action_type: 'assign_user'
    )
    assert_not_predicate rule, :valid?
    assert rule.errors[:action_value].present?
  end

  def test_validates_action_type_inclusion
    rule = DevelopmentIntegrationAutomationRule.new(
      project: @project,
      event_type: 'pr_opened',
      action_type: 'invalid_action',
      action_value: 'foo'
    )
    assert_not_predicate rule, :valid?
    assert rule.errors[:action_type].present?
  end

  def test_validates_active_boolean
    rule = DevelopmentIntegrationAutomationRule.new(
      project: @project,
      event_type: 'pr_opened',
      action_type: 'assign_user',
      action_value: 'developer1',
      active: nil
    )
    assert_not_predicate rule, :valid?
    assert rule.errors[:active].present?
  end

  def test_default_active_is_true
    rule = DevelopmentIntegrationAutomationRule.create!(
      project: @project,
      event_type: 'pr_opened',
      action_type: 'assign_user',
      action_value: 'developer1'
    )
    assert_equal true, rule.active
  end

  def test_belongs_to_project
    rule = DevelopmentIntegrationAutomationRule.create!(
      project: @project,
      event_type: 'pr_opened',
      action_type: 'assign_user',
      action_value: 'developer1'
    )
    assert_equal @project, rule.project
  end

  def test_accepts_all_valid_action_types
    DevelopmentIntegrationAutomationRule::VALID_ACTION_TYPES.each do |action_type|
      rule = DevelopmentIntegrationAutomationRule.new(
        project: @project,
        event_type: 'pr_opened',
        action_type: action_type,
        action_value: 'value'
      )
      assert_predicate rule, :valid?, "Expected #{action_type} to be valid"
    end
  end

  def test_active_scope_excludes_inactive
    active_rule = DevelopmentIntegrationAutomationRule.create!(
      project: @project,
      event_type: 'pr_opened',
      action_type: 'assign_user',
      action_value: 'developer1',
      active: true
    )
    inactive_rule = DevelopmentIntegrationAutomationRule.create!(
      project: @project,
      event_type: 'pr_opened',
      action_type: 'set_priority',
      action_value: 'Normal',
      active: false
    )

    active_ids = DevelopmentIntegrationAutomationRule.active.pluck(:id)
    assert_includes active_ids, active_rule.id
    assert_not_includes active_ids, inactive_rule.id
  end

  def test_for_event_finds_matching_rules
    rule1 = DevelopmentIntegrationAutomationRule.create!(
      project: @project,
      event_type: 'pr_opened',
      action_type: 'assign_user',
      action_value: 'developer1'
    )
    DevelopmentIntegrationAutomationRule.create!(
      project: @project,
      event_type: 'branch_created',
      action_type: 'assign_user',
      action_value: 'developer1'
    )

    results = DevelopmentIntegrationAutomationRule.for_event(@project, 'pr_opened')
    assert_equal 1, results.count
    assert_equal rule1.id, results.first.id
  end

  def test_for_event_filters_by_environment_name
    rule_with_env = DevelopmentIntegrationAutomationRule.create!(
      project: @project,
      event_type: 'deployment_success',
      action_type: 'assign_user',
      action_value: 'developer1',
      environment_name: 'staging'
    )
    DevelopmentIntegrationAutomationRule.create!(
      project: @project,
      event_type: 'deployment_success',
      action_type: 'assign_user',
      action_value: 'developer1',
      environment_name: 'production'
    )

    results = DevelopmentIntegrationAutomationRule.for_event(@project, 'deployment_success', environment_name: 'staging')
    assert_equal 1, results.count
    assert_equal rule_with_env.id, results.first.id
  end

  def test_for_event_excludes_inactive_rules
    DevelopmentIntegrationAutomationRule.create!(
      project: @project,
      event_type: 'pr_opened',
      action_type: 'assign_user',
      action_value: 'developer1',
      active: false
    )

    results = DevelopmentIntegrationAutomationRule.for_event(@project, 'pr_opened')
    assert_equal 0, results.count
  end

  def test_for_event_returns_none_without_project
    results = DevelopmentIntegrationAutomationRule.for_event(nil, 'pr_opened')
    assert_equal 0, results.count
  end

  def test_for_event_returns_none_without_event_type
    DevelopmentIntegrationAutomationRule.create!(
      project: @project,
      event_type: 'pr_opened',
      action_type: 'assign_user',
      action_value: 'developer1'
    )

    results = DevelopmentIntegrationAutomationRule.for_event(@project, nil)
    assert_equal 0, results.count
  end

  def test_dedup_marker_includes_rule_id_and_issue_id
    rule = DevelopmentIntegrationAutomationRule.create!(
      project: @project,
      event_type: 'pr_opened',
      action_type: 'assign_user',
      action_value: 'developer1'
    )

    marker = rule.dedup_marker(42)
    assert_equal "auto_rule:#{rule.id}:42", marker
  end
end
