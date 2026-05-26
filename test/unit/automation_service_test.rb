# frozen_string_literal: true

require_relative '../test_helper'

class AutomationServiceTest < ActiveSupport::TestCase
  fixtures :projects, :issue_statuses

  def setup
    @service = RedmineDevIntegration::AutomationService.new
    @project = projects(:projects_001)
    @issue = Issue.generate!(project: @project, subject: 'Automation target')
    @setting = DevelopmentIntegrationProjectSetting.create!(project: @project)
  end

  def test_automation_is_disabled_by_default_and_does_not_change_status
    original_status_id = @issue.status_id

    result = @service.call(issue: @issue, event_type: 'pr_opened', project: @project, marker: 'github:pr:save-failure:pr_opened:1')

    assert_equal original_status_id, @issue.reload.status_id
    assert_predicate result, :skipped?
    assert_equal 'disabled', result.message
  end

  def test_unknown_event_is_a_no_op
    @setting.update!(automation_enabled: true)
    original_status_id = @issue.status_id

    result = @service.call(issue: @issue, event_type: 'something_else', project: @project)

    assert_equal original_status_id, @issue.reload.status_id
    assert_predicate result, :skipped?
    assert_equal 'unknown_event', result.message
  end

  def test_enabled_without_mapping_is_a_no_op
    @setting.update!(automation_enabled: true)
    original_status_id = @issue.status_id

    result = @service.call(issue: @issue, event_type: 'pr_opened', project: @project)

    assert_equal original_status_id, @issue.reload.status_id
    assert_predicate result, :skipped?
    assert_equal 'missing_mapping', result.message
  end

  def test_enabled_mapped_pr_opened_changes_status_and_adds_note
    target_status = issue_statuses(:issue_statuses_002)
    @setting.update!(
      automation_enabled: true,
      pr_opened_status: target_status
    )
    external_provider_event = create_external_provider_event
    marker = 'github:pr:7:pr_opened:1'

    assert_difference 'ExternalAutomationEvent.count', 1 do
      result = @service.call(
        issue: @issue,
        event_type: 'pr_opened',
        project: @project,
        note: 'PR opened note',
        marker: marker,
        external_provider_event: external_provider_event
      )

      assert_predicate result, :processed?
      assert_equal "updated_status:#{target_status.id}", result.message
    end

    assert_equal target_status.id, @issue.reload.status_id
    assert_includes @issue.journals.last.notes, '[redmine-dev-integration:github:pr:7:pr_opened:1]'
    assert_includes @issue.journals.last.notes, 'PR opened note'
    assert_equal external_provider_event.id, ExternalAutomationEvent.last.external_provider_event_id
  end

  def test_enabled_mapped_branch_created_changes_status_and_adds_note
    target_status = issue_statuses(:issue_statuses_001)
    @setting.update!(
      automation_enabled: true,
      branch_created_status: target_status
    )

    result = @service.call(
      issue: @issue,
      event_type: 'branch_created',
      project: @project,
      note: 'Branch created note',
      marker: 'github:branch:7:branch_created:1'
    )

    assert_predicate result, :processed?
    assert_equal target_status.id, @issue.reload.status_id
    assert_equal "updated_status:#{target_status.id}", result.message
    assert_includes @issue.journals.last.notes, '[redmine-dev-integration:github:branch:7:branch_created:1]'
    assert_includes @issue.journals.last.notes, 'Branch created note'
  end

  def test_enabled_mapped_pr_merged_changes_status_and_adds_note
    target_status = issue_statuses(:issue_statuses_003)
    @setting.update!(
      automation_enabled: true,
      pr_merged_status: target_status
    )

    result = @service.call(
      issue: @issue,
      event_type: 'pr_merged',
      project: @project,
      note: 'PR merged note',
      marker: 'github:pr:7:pr_merged:1'
    )

    assert_predicate result, :processed?
    assert_equal target_status.id, @issue.reload.status_id
    assert_equal "updated_status:#{target_status.id}", result.message
    assert_includes @issue.journals.last.notes, '[redmine-dev-integration:github:pr:7:pr_merged:1]'
    assert_includes @issue.journals.last.notes, 'PR merged note'
  end

  def test_pr_closed_without_merge_adds_note_only_when_enabled
    @setting.update!(automation_enabled: true, pr_closed_note_enabled: false)

    skipped = @service.call(issue: @issue, event_type: 'pr_closed_without_merge', project: @project, note: 'Closed note', marker: 'github:pr:7:pr_closed_without_merge:1')

    assert_predicate skipped, :skipped?
    assert_equal 'disabled', skipped.message
    assert_equal 0, @issue.journals.count

    @setting.update!(pr_closed_note_enabled: true)

    processed = @service.call(issue: @issue, event_type: 'pr_closed_without_merge', project: @project, note: 'Closed note', marker: 'github:pr:7:pr_closed_without_merge:2')

    assert_predicate processed, :processed?
    assert_equal 'added_note', processed.message
    assert_includes @issue.reload.journals.last.notes, '[redmine-dev-integration:github:pr:7:pr_closed_without_merge:2]'
    assert_includes @issue.reload.journals.last.notes, 'Closed note'
  end

  def test_enabled_mapped_build_success_changes_status
    target_status = issue_statuses(:issue_statuses_001)
    @setting.update!(
      automation_enabled: true,
      build_success_status: target_status
    )

    result = @service.call(
      issue: @issue,
      event_type: 'build_success',
      project: @project,
      marker: 'build:github:101:build_success'
    )

    assert_predicate result, :processed?
    assert_equal target_status.id, @issue.reload.status_id
    assert_equal "updated_status:#{target_status.id}", result.message
    assert_includes @issue.journals.last.notes, '[redmine-dev-integration:build:github:101:build_success]'
  end

  def test_enabled_build_failed_adds_note_and_deduplicates
    @setting.update!(
      automation_enabled: true,
      build_failed_note_enabled: true
    )

    assert_difference 'Journal.count', 1 do
      result = @service.call(
        issue: @issue,
        event_type: 'build_failed',
        project: @project,
        note: 'Build failed: CI build',
        marker: 'build:github:101:build_failed'
      )
      assert_predicate result, :processed?
    end

    assert_no_difference 'Journal.count' do
      result = @service.call(
        issue: @issue,
        event_type: 'build_failed',
        project: @project,
        note: 'Build failed: CI build',
        marker: 'build:github:101:build_failed'
      )
      assert_predicate result, :skipped?
      assert_equal 'duplicate', result.message
    end
  end

  def test_enabled_mapped_deployment_success_changes_status_for_staging_and_production
    staging_status = issue_statuses(:issue_statuses_002)
    production_status = issue_statuses(:issue_statuses_003)
    @setting.update!(
      automation_enabled: true,
      deployment_staging_success_status: staging_status,
      deployment_production_success_status: production_status
    )

    staging_result = @service.call(
      issue: @issue,
      event_type: 'deployment_staging_success',
      project: @project,
      marker: 'deployment:github:201:deployment_staging_success'
    )

    assert_predicate staging_result, :processed?
    assert_equal staging_status.id, @issue.reload.status_id

    production_result = @service.call(
      issue: @issue,
      event_type: 'deployment_production_success',
      project: @project,
      marker: 'deployment:github:202:deployment_production_success'
    )

    assert_predicate production_result, :processed?
    assert_equal production_status.id, @issue.reload.status_id
  end

  def test_enabled_deployment_failed_can_add_note_and_change_status
    target_status = issue_statuses(:issue_statuses_001)
    @setting.update!(
      automation_enabled: true,
      deployment_failed_note_enabled: true,
      deployment_failed_status: target_status
    )

    result = @service.call(
      issue: @issue,
      event_type: 'deployment_failed',
      project: @project,
      note: 'Deployment failed: staging',
      marker: 'deployment:github:301:deployment_failed'
    )

    assert_predicate result, :processed?
    assert_equal target_status.id, @issue.reload.status_id
    assert_equal "updated_status:#{target_status.id}", result.message
    assert_includes @issue.journals.last.notes, 'Deployment failed: staging'
    assert_includes @issue.journals.last.notes, '[redmine-dev-integration:deployment:github:301:deployment_failed]'
  end

  def test_enabled_deployment_failed_without_mapping_can_add_note_only
    @setting.update!(
      automation_enabled: true,
      deployment_failed_note_enabled: true,
      deployment_failed_status_id: nil
    )

    result = @service.call(
      issue: @issue,
      event_type: 'deployment_failed',
      project: @project,
      note: 'Deployment failed: staging',
      marker: 'deployment:github:302:deployment_failed'
    )

    assert_predicate result, :processed?
    assert_equal 'added_note', result.message
    assert_includes @issue.reload.journals.last.notes, 'Deployment failed: staging'
  end

  def test_repeated_marker_skips_duplicate_journal
    target_status = issue_statuses(:issue_statuses_002)
    @setting.update!(
      automation_enabled: true,
      pr_opened_status: target_status
    )

    assert_difference 'Journal.count', 1 do
      result = @service.call(
        issue: @issue,
        event_type: 'pr_opened',
        project: @project,
        note: 'PR opened note',
        marker: 'github:pr:7:pr_opened:1'
      )
      assert_predicate result, :processed?
    end

    assert_no_difference 'Journal.count' do
      result = @service.call(
        issue: @issue,
        event_type: 'pr_opened',
        project: @project,
        note: 'PR opened note',
        marker: 'github:pr:7:pr_opened:1'
      )
      assert_predicate result, :skipped?
      assert_equal 'duplicate', result.message
    end
  end

  def test_existing_external_automation_event_skips_duplicate_status_change
    target_status = issue_statuses(:issue_statuses_002)
    @setting.update!(
      automation_enabled: true,
      pr_opened_status: target_status
    )
    marker = 'github:pr:existing:pr_opened:1'
    original_status_id = @issue.status_id

    ExternalAutomationEvent.create!(
      issue_id: @issue.id,
      marker: marker,
      action_type: 'set_pr_opened_status'
    )

    assert_no_difference 'Journal.count' do
      result = @service.call(
        issue: @issue,
        event_type: 'pr_opened',
        project: @project,
        note: 'PR opened note',
        marker: marker
      )

      assert_predicate result, :skipped?
      assert_equal 'duplicate', result.message
    end

    assert_equal original_status_id, @issue.reload.status_id
  end

  def test_record_not_unique_is_treated_as_duplicate_skip
    target_status = issue_statuses(:issue_statuses_002)
    @setting.update!(
      automation_enabled: true,
      pr_opened_status: target_status
    )
    original_status_id = @issue.status_id

    ExternalAutomationEvent.stubs(:create!).raises(ActiveRecord::RecordNotUnique)

    assert_no_difference 'Journal.count' do
      result = @service.call(
        issue: @issue,
        event_type: 'pr_opened',
        project: @project,
        note: 'PR opened note',
        marker: 'github:pr:race:pr_opened:1'
      )

      assert_predicate result, :skipped?
      assert_equal 'duplicate', result.message
    end

    assert_equal original_status_id, @issue.reload.status_id
  end

  def test_invalid_transition_or_save_failure_returns_failure_without_persisting_changes
    target_status = issue_statuses(:issue_statuses_002)
    @setting.update!(
      automation_enabled: true,
      pr_opened_status: target_status
    )
    original_status_id = @issue.status_id
    @issue.stubs(:save).returns(false)
    @issue.expects(:init_journal).with(User.current, '[redmine-dev-integration:github:pr:save-failure:pr_opened:1]')

    assert_no_difference 'Journal.count' do
      result = @service.call(issue: @issue, event_type: 'pr_opened', project: @project, marker: 'github:pr:save-failure:pr_opened:1')

      assert_equal original_status_id, @issue.reload.status_id
      assert_predicate result, :failure?
      assert_match(/./, result.message)
    end
  end

  def test_deployment_success_with_environment_rule_changes_status
    target_status = issue_statuses(:issue_statuses_003)
    DevelopmentIntegrationEnvironmentRule.create!(
      project: @project,
      environment_name: 'qa',
      success_status: target_status
    )
    @setting.update!(automation_enabled: true)

    result = @service.call(
      issue: @issue,
      event_type: 'deployment_success',
      project: @project,
      environment_name: 'qa',
      marker: 'deployment:github:1:deployment_success'
    )

    assert_predicate result, :processed?
    assert_equal target_status.id, @issue.reload.status_id
    assert_equal "updated_status:#{target_status.id}", result.message
  end

  def test_deployment_failed_with_environment_rule_changes_status_and_note
    target_status = issue_statuses(:issue_statuses_001)
    DevelopmentIntegrationEnvironmentRule.create!(
      project: @project,
      environment_name: 'staging',
      failed_status: target_status,
      failed_note_enabled: true
    )
    @setting.update!(automation_enabled: true)

    result = @service.call(
      issue: @issue,
      event_type: 'deployment_failed',
      project: @project,
      environment_name: 'staging',
      note: 'Deploy failed: staging',
      marker: 'deployment:github:2:deployment_failed'
    )

    assert_predicate result, :processed?
    assert_equal target_status.id, @issue.reload.status_id
    assert_includes @issue.journals.last.notes, 'Deploy failed: staging'
    assert_equal "updated_status:#{target_status.id}", result.message
  end

  def test_deployment_failed_with_environment_rule_note_only_when_no_status_mapped
    DevelopmentIntegrationEnvironmentRule.create!(
      project: @project,
      environment_name: 'staging',
      failed_status_id: nil,
      failed_note_enabled: true
    )
    @setting.update!(automation_enabled: true)

    result = @service.call(
      issue: @issue,
      event_type: 'deployment_failed',
      project: @project,
      environment_name: 'staging',
      note: 'Deploy failed: staging',
      marker: 'deployment:github:3:deployment_failed'
    )

    assert_predicate result, :processed?
    assert_equal 'added_note', result.message
    assert_includes @issue.reload.journals.last.notes, 'Deploy failed: staging'
  end

  def test_deployment_success_falls_back_to_legacy_when_no_environment_rule
    target_status = issue_statuses(:issue_statuses_002)
    @setting.update!(
      automation_enabled: true,
      deployment_staging_success_status: target_status
    )

    result = @service.call(
      issue: @issue,
      event_type: 'deployment_success',
      project: @project,
      environment_name: 'staging',
      marker: 'deployment:github:4:deployment_success'
    )

    assert_predicate result, :processed?
    assert_equal target_status.id, @issue.reload.status_id
  end

  def test_deployment_success_skips_when_no_environment_rule_and_no_legacy_mapping
    @setting.update!(automation_enabled: true)

    result = @service.call(
      issue: @issue,
      event_type: 'deployment_success',
      project: @project,
      environment_name: 'unknown-env',
      marker: 'deployment:github:5:deployment_success'
    )

    assert_predicate result, :skipped?
    assert_equal 'missing_mapping', result.message
  end

  def test_deployment_failed_falls_back_to_legacy_when_no_environment_rule
    target_status = issue_statuses(:issue_statuses_001)
    @setting.update!(
      automation_enabled: true,
      deployment_failed_status: target_status,
      deployment_failed_note_enabled: true
    )

    result = @service.call(
      issue: @issue,
      event_type: 'deployment_failed',
      project: @project,
      environment_name: 'nonexistent-env',
      note: 'Deploy failed',
      marker: 'deployment:github:6:deployment_failed'
    )

    assert_predicate result, :processed?
    assert_equal target_status.id, @issue.reload.status_id
  end

  def test_environment_rule_preferred_over_legacy_setting_when_both_exist
    env_target_status = issue_statuses(:issue_statuses_003)
    legacy_status = issue_statuses(:issue_statuses_001)
    DevelopmentIntegrationEnvironmentRule.create!(
      project: @project,
      environment_name: 'staging',
      success_status: env_target_status
    )
    @setting.update!(
      automation_enabled: true,
      deployment_staging_success_status: legacy_status
    )

    result = @service.call(
      issue: @issue,
      event_type: 'deployment_success',
      project: @project,
      environment_name: 'staging',
      marker: 'deployment:github:7:deployment_success'
    )

    assert_predicate result, :processed?
    assert_equal env_target_status.id, @issue.reload.status_id
    assert_not_equal legacy_status.id, @issue.reload.status_id
  end

  def test_case_insensitive_environment_name_matching
    target_status = issue_statuses(:issue_statuses_002)
    DevelopmentIntegrationEnvironmentRule.create!(
      project: @project,
      environment_name: 'Production',
      success_status: target_status
    )
    @setting.update!(automation_enabled: true)

    result = @service.call(
      issue: @issue,
      event_type: 'deployment_success',
      project: @project,
      environment_name: 'PRODUCTION',
      marker: 'deployment:github:8:deployment_success'
    )

    assert_predicate result, :processed?
    assert_equal target_status.id, @issue.reload.status_id
  end

  def test_existing_deployment_staging_success_still_works
    target_status = issue_statuses(:issue_statuses_002)
    @setting.update!(
      automation_enabled: true,
      deployment_staging_success_status: target_status
    )

    result = @service.call(
      issue: @issue,
      event_type: 'deployment_staging_success',
      project: @project,
      marker: 'deployment:github:9:deployment_staging_success'
    )

    assert_predicate result, :processed?
    assert_equal target_status.id, @issue.reload.status_id
  end

  def test_existing_deployment_production_success_still_works
    target_status = issue_statuses(:issue_statuses_003)
    @setting.update!(
      automation_enabled: true,
      deployment_production_success_status: target_status
    )

    result = @service.call(
      issue: @issue,
      event_type: 'deployment_production_success',
      project: @project,
      marker: 'deployment:github:10:deployment_production_success'
    )

    assert_predicate result, :processed?
    assert_equal target_status.id, @issue.reload.status_id
  end

  def test_existing_deployment_failed_without_environment_name_still_works
    target_status = issue_statuses(:issue_statuses_001)
    @setting.update!(
      automation_enabled: true,
      deployment_failed_status: target_status,
      deployment_failed_note_enabled: true
    )

    result = @service.call(
      issue: @issue,
      event_type: 'deployment_failed',
      project: @project,
      note: 'Deploy failed',
      marker: 'deployment:github:11:deployment_failed'
    )

    assert_predicate result, :processed?
    assert_equal target_status.id, @issue.reload.status_id
  end

  # --- Automation Rule tests ---

  def test_assign_user_rule_changes_assigned_to
    user = User.generate!(login: 'auto_tester')
    DevelopmentIntegrationAutomationRule.create!(
      project: @project,
      event_type: 'pr_opened',
      action_type: 'assign_user',
      action_value: 'auto_tester'
    )
    @setting.update!(automation_enabled: true)

    result = @service.call(
      issue: @issue,
      event_type: 'pr_opened',
      project: @project,
      note: 'Assigning via rule'
    )

    assert_predicate result, :processed?
    assert_equal user.id, @issue.reload.assigned_to_id
  end

  def test_set_priority_rule_changes_priority
    priority = IssuePriority.find_by(name: 'Normal') || IssuePriority.generate!(name: 'Normal')
    DevelopmentIntegrationAutomationRule.create!(
      project: @project,
      event_type: 'pr_opened',
      action_type: 'set_priority',
      action_value: 'Normal'
    )
    @setting.update!(automation_enabled: true)

    result = @service.call(
      issue: @issue,
      event_type: 'pr_opened',
      project: @project,
      note: 'Setting priority via rule'
    )

    assert_predicate result, :processed?
    assert_equal priority.id, @issue.reload.priority_id
  end

  def test_set_custom_field_rule_changes_custom_field_value
    field = IssueCustomField.generate!(name: 'TestField', field_format: 'string', is_for_all: true, trackers: [@issue.tracker])
    DevelopmentIntegrationAutomationRule.create!(
      project: @project,
      event_type: 'pr_opened',
      action_type: 'set_custom_field',
      action_value: "#{field.id}:custom_value"
    )
    @setting.update!(automation_enabled: true)

    result = @service.call(
      issue: @issue,
      event_type: 'pr_opened',
      project: @project,
      note: 'Setting custom field via rule'
    )

    assert_predicate result, :processed?
    assert_equal 'custom_value', @issue.reload.custom_field_value(field)
  end

  def test_change_status_rule_changes_status_by_name
    target_status = issue_statuses(:issue_statuses_003)
    DevelopmentIntegrationAutomationRule.create!(
      project: @project,
      event_type: 'pr_opened',
      action_type: 'change_status',
      action_value: target_status.name
    )
    @setting.update!(automation_enabled: true)

    result = @service.call(
      issue: @issue,
      event_type: 'pr_opened',
      project: @project,
      note: 'Changing status via rule'
    )

    assert_predicate result, :processed?
    assert_equal target_status.id, @issue.reload.status_id
  end

  def test_add_note_rule_adds_journal_note
    DevelopmentIntegrationAutomationRule.create!(
      project: @project,
      event_type: 'pr_opened',
      action_type: 'add_note',
      action_value: 'Rule-based note text'
    )
    @setting.update!(automation_enabled: true)

    assert_difference 'Journal.count', 1 do
      result = @service.call(
        issue: @issue,
        event_type: 'pr_opened',
        project: @project,
        note: 'Rule-based note text'
      )
      assert_predicate result, :processed?
    end

    assert_includes @issue.reload.journals.last.notes, 'Rule-based note text'
  end

  def test_multiple_rules_for_same_event_all_execute
    user = User.generate!(login: 'multi_assign')
    priority = IssuePriority.find_by(name: 'Normal') || IssuePriority.generate!(name: 'Normal')

    DevelopmentIntegrationAutomationRule.create!(
      project: @project,
      event_type: 'pr_opened',
      action_type: 'assign_user',
      action_value: 'multi_assign'
    )
    DevelopmentIntegrationAutomationRule.create!(
      project: @project,
      event_type: 'pr_opened',
      action_type: 'set_priority',
      action_value: 'Normal'
    )
    @setting.update!(automation_enabled: true)

    result = @service.call(
      issue: @issue,
      event_type: 'pr_opened',
      project: @project
    )

    assert_predicate result, :processed?
    assert_equal user.id, @issue.reload.assigned_to_id
    assert_equal priority.id, @issue.reload.priority_id
  end

  def test_invalid_rule_action_value_is_skipped_with_error_log
    DevelopmentIntegrationAutomationRule.create!(
      project: @project,
      event_type: 'pr_opened',
      action_type: 'assign_user',
      action_value: 'nonexistent_user_login'
    )
    @setting.update!(automation_enabled: true)

    result = @service.call(
      issue: @issue,
      event_type: 'pr_opened',
      project: @project
    )

    assert_predicate result, :failure?
    assert_equal 'user_not_found', result.message
  end

  def test_existing_automation_behavior_unchanged_with_rules_present
    target_status = issue_statuses(:issue_statuses_002)
    @setting.update!(
      automation_enabled: true,
      pr_opened_status: target_status
    )

    DevelopmentIntegrationAutomationRule.create!(
      project: @project,
      event_type: 'pr_opened',
      action_type: 'assign_user',
      action_value: 'someone'
    )

    result = @service.call(
      issue: @issue,
      event_type: 'pr_opened',
      project: @project,
      note: 'PR opened note',
      marker: 'github:pr:existing:pr_opened:1'
    )

    assert_predicate result, :processed?
    assert_equal target_status.id, @issue.reload.status_id
  end

  def test_automation_rule_dedup_prevents_duplicate_execution
    user = User.generate!(login: 'dedup_user')
    rule = DevelopmentIntegrationAutomationRule.create!(
      project: @project,
      event_type: 'pr_opened',
      action_type: 'assign_user',
      action_value: 'dedup_user'
    )
    @setting.update!(automation_enabled: true)
    marker = rule.dedup_marker(@issue.id)

    ExternalAutomationEvent.create!(
      issue_id: @issue.id,
      marker: marker,
      action_type: 'assign_user'
    )

    assert_no_difference 'Journal.count' do
      result = @service.call(
        issue: @issue,
        event_type: 'pr_opened',
        project: @project,
        note: 'Should skip'
      )
      assert_predicate result, :skipped?
      assert_equal 'duplicate', result.message
    end
  end

  def test_automation_rule_journals_mutation_with_marker
    user = User.generate!(login: 'journal_user')
    rule = DevelopmentIntegrationAutomationRule.create!(
      project: @project,
      event_type: 'pr_opened',
      action_type: 'assign_user',
      action_value: 'journal_user'
    )
    @setting.update!(automation_enabled: true)

    result = @service.call(
      issue: @issue,
      event_type: 'pr_opened',
      project: @project,
      note: 'Assigning developer'
    )

    assert_predicate result, :processed?
    expected_marker = "[redmine-dev-integration:#{rule.dedup_marker(@issue.id)}]"
    assert_includes @issue.reload.journals.last.notes, expected_marker
    assert_includes @issue.reload.journals.last.notes, 'Assigning developer'
  end

  def test_one_rule_failure_does_not_block_other_rules
    target_status = issue_statuses(:issue_statuses_003)

    DevelopmentIntegrationAutomationRule.create!(
      project: @project,
      event_type: 'pr_opened',
      action_type: 'assign_user',
      action_value: 'nonexistent_user'
    )
    DevelopmentIntegrationAutomationRule.create!(
      project: @project,
      event_type: 'pr_opened',
      action_type: 'change_status',
      action_value: target_status.name
    )
    @setting.update!(automation_enabled: true)

    result = @service.call(
      issue: @issue,
      event_type: 'pr_opened',
      project: @project
    )

    assert_predicate result, :processed?
    assert_equal target_status.id, @issue.reload.status_id
  end

  def test_automation_rule_selects_existing_result_when_processed
    target_status = issue_statuses(:issue_statuses_002)
    @setting.update!(
      automation_enabled: true,
      pr_opened_status: target_status
    )

    DevelopmentIntegrationAutomationRule.create!(
      project: @project,
      event_type: 'pr_opened',
      action_type: 'assign_user',
      action_value: 'some_other_user'
    )

    result = @service.call(
      issue: @issue,
      event_type: 'pr_opened',
      project: @project,
      note: 'Existing mapping takes priority',
      marker: 'github:pr:priority:pr_opened:1'
    )

    assert_predicate result, :processed?
    assert_equal target_status.id, @issue.reload.status_id
    assert_equal "updated_status:#{target_status.id}", result.message
  end

  private

  def create_external_provider_event
    ExternalProviderEvent.create!(
      provider: 'github',
      delivery_id: "delivery-#{Time.now.to_i}-#{rand(100000)}",
      event_type: 'pull_request',
      payload: '{}',
      status: 'pending'
    )
  end
end
