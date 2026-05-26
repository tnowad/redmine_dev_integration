# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/dev_integration_test_factory'

class AutomationRulesTest < ActiveSupport::TestCase
  include DevIntegrationTestFactory

  def setup
    @project = create_project_with_prefix(name: 'auto_rules', prefix: 'DEV')
    @issue = create_issue_with_key(project: @project, subject: 'Test')
    @service = RedmineDevIntegration::AutomationService.new
    DevelopmentIntegrationProjectSetting.create!(project: @project, automation_enabled: true)
  end

  def test_assign_user_rule_changes_assigned_to
    user = User.generate!(login: 'auto_assign_test')
    DevelopmentIntegrationAutomationRule.create!(
      project: @project,
      event_type: 'pr_opened',
      action_type: 'assign_user',
      action_value: 'auto_assign_test',
      active: true
    )

    result = @service.call(
      issue: @issue,
      event_type: 'pr_opened',
      project: @project,
      marker: "test:marker:#{SecureRandom.hex(4)}",
      note: 'PR opened by dev1 | https://github.com/owner/repo/pull/42'
    )

    assert_predicate result, :processed?
    assert_equal user.id, @issue.reload.assigned_to_id
    assert_equal 'assign_user', result.action
  end

  def test_set_priority_rule_changes_priority
    priority = IssuePriority.find_by(name: 'Normal') || IssuePriority.generate!(name: 'Normal')
    DevelopmentIntegrationAutomationRule.create!(
      project: @project,
      event_type: 'pr_opened',
      action_type: 'set_priority',
      action_value: 'Normal',
      active: true
    )

    result = @service.call(
      issue: @issue,
      event_type: 'pr_opened',
      project: @project,
      marker: "test:marker:#{SecureRandom.hex(4)}",
      note: 'Setting priority via rule'
    )

    assert_predicate result, :processed?
    assert_equal priority.id, @issue.reload.priority_id
    assert_equal 'set_priority', result.action
  end

  def test_set_custom_field_rule_changes_custom_field_value
    field = IssueCustomField.generate!(name: 'TestField', field_format: 'string', is_for_all: true, trackers: [@issue.tracker])
    DevelopmentIntegrationAutomationRule.create!(
      project: @project,
      event_type: 'pr_opened',
      action_type: 'set_custom_field',
      action_value: "#{field.id}:custom_value",
      active: true
    )

    result = @service.call(
      issue: @issue,
      event_type: 'pr_opened',
      project: @project,
      marker: "test:marker:#{SecureRandom.hex(4)}",
      note: 'Setting custom field via rule'
    )

    assert_predicate result, :processed?
    assert_equal 'custom_value', @issue.reload.custom_field_value(field)
    assert_equal 'set_custom_field', result.action
  end

  def test_change_status_rule_changes_status
    target_status = IssueStatus.find_by(name: 'Resolved') || IssueStatus.generate!(name: 'Resolved')
    DevelopmentIntegrationAutomationRule.create!(
      project: @project,
      event_type: 'pr_opened',
      action_type: 'change_status',
      action_value: target_status.name,
      active: true
    )

    result = @service.call(
      issue: @issue,
      event_type: 'pr_opened',
      project: @project,
      marker: "test:marker:#{SecureRandom.hex(4)}",
      note: 'Changing status via rule'
    )

    assert_predicate result, :processed?
    assert_equal target_status.id, @issue.reload.status_id
    assert_equal 'change_status', result.action
  end

  def test_add_note_rule_adds_journal_note
    DevelopmentIntegrationAutomationRule.create!(
      project: @project,
      event_type: 'pr_opened',
      action_type: 'add_note',
      action_value: 'Rule-based note text from automation',
      active: true
    )

    assert_difference 'Journal.count', 1 do
      result = @service.call(
        issue: @issue,
        event_type: 'pr_opened',
        project: @project,
        marker: "test:marker:#{SecureRandom.hex(4)}",
        note: 'Rule-based note text from automation'
      )

      assert_predicate result, :processed?
      assert_equal 'add_note', result.action
      assert_equal 'added_note', result.message
    end

    assert_includes @issue.reload.journals.last.notes, 'Rule-based note text from automation'
  end

  def test_multiple_rules_for_same_event_both_execute
    user = User.generate!(login: 'multi_assign_user')
    priority = IssuePriority.find_by(name: 'Normal') || IssuePriority.generate!(name: 'Normal')

    DevelopmentIntegrationAutomationRule.create!(
      project: @project,
      event_type: 'pr_merged',
      action_type: 'assign_user',
      action_value: 'multi_assign_user',
      active: true
    )
    DevelopmentIntegrationAutomationRule.create!(
      project: @project,
      event_type: 'pr_merged',
      action_type: 'set_priority',
      action_value: 'Normal',
      active: true
    )

    result = @service.call(
      issue: @issue,
      event_type: 'pr_merged',
      project: @project,
      marker: "test:marker:#{SecureRandom.hex(4)}",
      note: 'PR merged by dev1'
    )

    assert_predicate result, :processed?
    assert_equal user.id, @issue.reload.assigned_to_id
    assert_equal priority.id, @issue.reload.priority_id
  end

  def test_rule_dedup_prevents_reexecution
    DevelopmentIntegrationAutomationRule.create!(
      project: @project,
      event_type: 'pr_opened',
      action_type: 'assign_user',
      action_value: 'admin',
      active: true
    )

    marker = "test:marker:#{SecureRandom.hex(4)}"

    assert_difference 'Journal.count', 1 do
      result = @service.call(
        issue: @issue,
        event_type: 'pr_opened',
        project: @project,
        marker: marker,
        note: 'PR opened first time'
      )
      assert_predicate result, :processed?
    end

    assert_no_difference 'Journal.count' do
      result = @service.call(
        issue: @issue,
        event_type: 'pr_opened',
        project: @project,
        marker: marker,
        note: 'PR opened second time should skip'
      )
      assert_predicate result, :skipped?
      assert_equal 'duplicate', result.message
    end
  end

  def test_rule_skipped_when_automation_disabled
    setting = DevelopmentIntegrationProjectSetting.for_project(@project)
    setting.update!(automation_enabled: false)

    DevelopmentIntegrationAutomationRule.create!(
      project: @project,
      event_type: 'pr_opened',
      action_type: 'assign_user',
      action_value: 'admin',
      active: false
    )

    result = @service.call(
      issue: @issue,
      event_type: 'pr_opened',
      project: @project,
      marker: "test:marker:#{SecureRandom.hex(4)}",
      note: 'Should be skipped'
    )

    assert_predicate result, :skipped?
    assert_equal 'disabled', result.message
  end

  def test_invalid_action_value_handled_gracefully
    DevelopmentIntegrationAutomationRule.create!(
      project: @project,
      event_type: 'pr_opened',
      action_type: 'assign_user',
      action_value: 'nonexistent_user_login',
      active: true
    )

    result = @service.call(
      issue: @issue,
      event_type: 'pr_opened',
      project: @project,
      marker: "test:marker:#{SecureRandom.hex(4)}",
      note: 'Should fail gracefully'
    )

    assert_predicate result, :failure?
    assert_equal 'user_not_found', result.message
  end
end
