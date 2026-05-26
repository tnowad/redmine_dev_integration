# frozen_string_literal: true

require_relative '../test_helper'

class SmartCommitServiceTest < ActiveSupport::TestCase
  fixtures :projects, :issue_statuses, :enumerations

  def setup
    @project = projects(:projects_001)
    DevelopmentIntegrationProjectSetting.where(project: @project).destroy_all
    @setting = DevelopmentIntegrationProjectSetting.create!(project: @project)
    @issue = Issue.generate!(project: @project, subject: 'Smart commit target', assigned_to: nil, issue_key: 'RAK-1')
    @service = RedmineDevIntegration::SmartCommitService.new
    @commit_sha = 'abc123def456789012345678901234567890abcd'
  end

  def test_disabled_by_default_returns_empty
    results = @service.call(
      project: @project,
      commit_sha: @commit_sha,
      commit_message: 'RAK-1 #done'
    )
    assert_equal [], results
  end

  def test_enabled_comment_adds_note
    @setting.update!(smart_commits_enabled: true)

    assert_difference 'Journal.count', 1 do
      results = @service.call(
        project: @project,
        commit_sha: @commit_sha,
        commit_message: 'RAK-1 #comment Fixed the bug'
      )

      assert_equal 1, results.size
      assert_predicate results[0], :processed?
      assert_equal 'added_note', results[0].message
    end

    assert_includes @issue.reload.journals.last.notes, 'Fixed the bug'
  end

  def test_comment_deduplication
    @setting.update!(smart_commits_enabled: true)
    message = 'RAK-1 #comment Fixed the bug'

    assert_difference 'Journal.count', 1 do
      @service.call(project: @project, commit_sha: @commit_sha, commit_message: message)
    end

    assert_no_difference 'Journal.count' do
      results = @service.call(project: @project, commit_sha: @commit_sha, commit_message: message)
      assert_predicate results[0], :skipped?
      assert_equal 'duplicate', results[0].message
    end
  end

  def test_done_changes_status_when_mapped
    target_status = issue_statuses(:issue_statuses_002)
    @setting.update!(
      smart_commits_enabled: true,
      pr_merged_status: target_status
    )

    results = @service.call(
      project: @project,
      commit_sha: @commit_sha,
      commit_message: 'RAK-1 #done'
    )

    assert_equal 1, results.size
    assert_predicate results[0], :processed?
    assert_equal target_status.id, @issue.reload.status_id
  end

  def test_done_skipped_without_status_mapping
    @setting.update!(smart_commits_enabled: true, pr_merged_status_id: nil)

    results = @service.call(
      project: @project,
      commit_sha: @commit_sha,
      commit_message: 'RAK-1 #done'
    )

    assert_equal 1, results.size
    assert_predicate results[0], :skipped?
    assert_equal 'missing_status_mapping', results[0].message
  end

  def test_done_deduplication
    target_status = issue_statuses(:issue_statuses_002)
    @setting.update!(smart_commits_enabled: true, pr_merged_status: target_status)

    message = 'RAK-1 #done'

    assert_difference 'ExternalAutomationEvent.count', 1 do
      @service.call(project: @project, commit_sha: @commit_sha, commit_message: message)
    end

    assert_no_difference 'ExternalAutomationEvent.count' do
      results = @service.call(project: @project, commit_sha: @commit_sha, commit_message: message)
      assert_predicate results[0], :skipped?
      assert_equal 'duplicate', results[0].message
    end
  end

  def test_time_logs_entry
    @setting.update!(smart_commits_enabled: true)

    assert_difference 'TimeEntry.count', 1 do
      results = @service.call(
        project: @project,
        commit_sha: @commit_sha,
        commit_message: 'RAK-1 #time 1h'
      )

      assert_equal 1, results.size
      assert_predicate results[0], :processed?

      entry = TimeEntry.last
      assert_equal 1.0, entry.hours
      assert_equal @issue, entry.issue
    end
  end

  def test_time_parses_hours_and_minutes
    @setting.update!(smart_commits_enabled: true)

    assert_difference 'TimeEntry.count', 1 do
      results = @service.call(
        project: @project,
        commit_sha: @commit_sha,
        commit_message: 'RAK-1 #time 1h 30m'
      )

      assert_predicate results[0], :processed?
      assert_equal 1.5, TimeEntry.last.hours
    end
  end

  def test_time_with_minutes_only
    @setting.update!(smart_commits_enabled: true)

    assert_difference 'TimeEntry.count', 1 do
      results = @service.call(
        project: @project,
        commit_sha: @commit_sha,
        commit_message: 'RAK-1 #time 45m'
      )

      assert_predicate results[0], :processed?
      assert_equal 0.75, TimeEntry.last.hours
    end
  end

  def test_time_empty_duration_skipped
    @setting.update!(smart_commits_enabled: true)

    assert_no_difference 'TimeEntry.count' do
      results = @service.call(
        project: @project,
        commit_sha: @commit_sha,
        commit_message: 'RAK-1 #time'
      )

      assert_predicate results[0], :skipped?
    end
  end

  def test_time_deduplication
    @setting.update!(smart_commits_enabled: true)
    message = 'RAK-1 #time 2h'

    assert_difference 'TimeEntry.count', 1 do
      @service.call(project: @project, commit_sha: @commit_sha, commit_message: message)
    end

    assert_no_difference 'TimeEntry.count' do
      results = @service.call(project: @project, commit_sha: @commit_sha, commit_message: message)
      assert_predicate results[0], :skipped?
    end
  end

  def test_assign_sets_assignee
    @setting.update!(smart_commits_enabled: true)
    user = User.generate!(login: 'jdoe', firstname: 'John', lastname: 'Doe', mail: 'jdoe@example.org')
    User.add_to_project(user, @project)

    results = @service.call(
      project: @project,
      commit_sha: @commit_sha,
      commit_message: 'RAK-1 #assign jdoe'
    )

    assert_equal 1, results.size
    assert_predicate results[0], :processed?
    assert_equal user.id, @issue.reload.assigned_to_id
  end

  def test_assign_unknown_user_skipped
    @setting.update!(smart_commits_enabled: true)

    results = @service.call(
      project: @project,
      commit_sha: @commit_sha,
      commit_message: 'RAK-1 #assign nonexistent'
    )

    assert_predicate results[0], :skipped?
    assert_equal 'unknown_user', results[0].message
    assert_nil @issue.reload.assigned_to
  end

  def test_assign_deduplication
    @setting.update!(smart_commits_enabled: true)
    user = User.generate!(login: 'jdoe', firstname: 'John', lastname: 'Doe', mail: 'jdoe@example.org')
    User.add_to_project(user, @project)
    message = 'RAK-1 #assign jdoe'

    @service.call(project: @project, commit_sha: @commit_sha, commit_message: message)

    assert_no_difference 'ExternalAutomationEvent.count' do
      results = @service.call(project: @project, commit_sha: @commit_sha, commit_message: message)
      assert_predicate results[0], :skipped?
      assert_equal 'duplicate', results[0].message
    end
  end

  def test_multiple_commands_in_one_message
    target_status = issue_statuses(:issue_statuses_002)
    @setting.update!(smart_commits_enabled: true, pr_merged_status: target_status)

    results = @service.call(
      project: @project,
      commit_sha: @commit_sha,
      commit_message: 'RAK-1 #comment Fixed #done #time 1h'
    )

    assert_equal 3, results.size
    assert results.all?(&:processed?)
  end

  def test_different_commits_not_deduplicated
    @setting.update!(smart_commits_enabled: true)
    message = 'RAK-1 #comment Fixed'

    assert_difference 'Journal.count', 2 do
      results1 = @service.call(project: @project, commit_sha: 'aaa', commit_message: message)
      assert_predicate results1[0], :processed?

      results2 = @service.call(project: @project, commit_sha: 'bbb', commit_message: message)
      assert_predicate results2[0], :processed?
    end
  end

  def test_no_issue_key_no_commands
    @setting.update!(smart_commits_enabled: true)

    results = @service.call(
      project: @project,
      commit_sha: @commit_sha,
      commit_message: 'Just a regular commit'
    )

    assert_equal [], results
  end

  def test_issue_not_found_skips_commands
    @setting.update!(smart_commits_enabled: true)

    assert_no_difference 'Journal.count' do
      results = @service.call(
        project: @project,
        commit_sha: @commit_sha,
        commit_message: 'UNKNOWN-999 #done'
      )

      assert_equal [], results
    end
  end

  def test_assign_case_insensitive_login
    @setting.update!(smart_commits_enabled: true)
    user = User.generate!(login: 'JDoe', firstname: 'John', lastname: 'Doe', mail: 'jdoe@example.org')
    User.add_to_project(user, @project)

    results = @service.call(
      project: @project,
      commit_sha: @commit_sha,
      commit_message: 'RAK-1 #assign jdoe'
    )

    assert_predicate results[0], :processed?
    assert_equal user.id, @issue.reload.assigned_to_id
  end
end
