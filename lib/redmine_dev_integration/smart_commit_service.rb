# frozen_string_literal: true

module RedmineDevIntegration
  class SmartCommitService
    Result = Struct.new(:issue_key, :action, :status, :message, keyword_init: true) do
      def processed?
        status == :processed
      end

      def skipped?
        status == :skipped
      end

      def failure?
        status == :failure
      end
    end

    def self.call(project:, commit_sha:, commit_message:, user: nil)
      new.call(project: project, commit_sha: commit_sha, commit_message: commit_message, user: user)
    end

    def call(project:, commit_sha:, commit_message:, user: nil)
      return [] unless enabled_for?(project)

      @user = user || User.current

      commands = SmartCommitParser.parse(commit_message)
      return [] if commands.empty?

      results = []
      commands.each do |command|
        issue = resolve_issue(command.issue_key)
        next unless issue

        case command.action
        when :comment
          results << apply_comment(issue, command, commit_sha)
        when :done
          results << apply_done(issue, command, commit_sha, project)
        when :time
          results << apply_time(issue, command, commit_sha)
        when :assign
          results << apply_assign(issue, command, commit_sha)
        end
      end

      results
    end

    private

    def enabled_for?(project)
      return false unless project
      setting = project_setting(project)
      return false unless setting
      setting.smart_commits_enabled == true
    end

    def project_setting(project)
      return nil unless project&.respond_to?(:development_integration_project_setting)
      project.development_integration_project_setting || DevelopmentIntegrationProjectSetting.for_project(project)
    rescue StandardError
      nil
    end

    def resolve_issue(issue_key)
      return nil unless defined?(Issue) && Issue.respond_to?(:find_by_issue_key)

      Issue.find_by_issue_key(issue_key)
    end

    def marker(commit_sha, action, issue_id, value = nil)
      parts = ['smart_commit', commit_sha.to_s, action.to_s, issue_id.to_s]
      parts << value_hash(value) if value.present?
      parts.join(':')
    end

    def value_hash(value)
      value.to_s.hash.abs.to_s(36)
    end

    def apply_comment(issue, command, commit_sha)
      return skipped_result(command, :no_text) if command.value.blank?

      marker_str = marker(commit_sha, :comment, issue.id, command.value)

      if duplicate_automation_event?(issue, marker_str, :add_note)
        return skipped_result(command, :duplicate)
      end

      note = build_note(command.value, marker_str)

      issue.init_journal(@user, note)
      issue.save!

      create_automation_event(issue, marker_str, :add_note)

      Result.new(
        issue_key: command.issue_key,
        action: :comment,
        status: :processed,
        message: 'added_note'
      )
    rescue ActiveRecord::RecordNotUnique
      skipped_result(command, :duplicate)
    rescue StandardError => e
      failure_result(command, e.class.name.underscore)
    end

    def apply_done(issue, command, commit_sha, project)
      setting = project_setting(project)
      return skipped_result(command, :no_setting) unless setting

      status_id = setting.pr_merged_status_id
      return skipped_result(command, :missing_status_mapping) unless status_id

      status = IssueStatus.find_by(id: status_id)
      return skipped_result(command, :missing_status) unless status

      marker_str = marker(commit_sha, :done, issue.id)

      if duplicate_automation_event?(issue, marker_str, :set_status)
        return skipped_result(command, :duplicate)
      end

      issue.init_journal(@user, build_note("Smart commit: Marked as done (commit #{commit_sha[0..7]})", marker_str))
      issue.status = status
      issue.save!

      create_automation_event(issue, marker_str, :set_status)

      Result.new(
        issue_key: command.issue_key,
        action: :done,
        status: :processed,
        message: "updated_status:#{status.id}"
      )
    rescue ActiveRecord::RecordNotUnique
      skipped_result(command, :duplicate)
    rescue StandardError => e
      failure_result(command, e.class.name.underscore)
    end

    def apply_time(issue, command, commit_sha)
      return skipped_result(command, :no_duration) if command.value.blank?

      hours = parse_duration(command.value)
      return skipped_result(command, :invalid_duration) if hours.nil? || hours <= 0

      marker_str = marker(commit_sha, :time, issue.id, command.value)

      if duplicate_automation_event?(issue, marker_str, :log_time)
        return skipped_result(command, :duplicate)
      end

      activity = time_entry_activity
      unless activity
        return skipped_result(command, :no_activity)
      end

      TimeEntry.create!(
        project: issue.project,
        issue: issue,
        user: @user,
        activity: activity,
        hours: hours,
        spent_on: @user.today || Time.zone.today,
        comments: "Smart commit: #{commit_sha[0..7]}"
      )

      create_automation_event(issue, marker_str, :log_time)

      Result.new(
        issue_key: command.issue_key,
        action: :time,
        status: :processed,
        message: "logged_time:#{hours}h"
      )
    rescue ActiveRecord::RecordNotUnique
      skipped_result(command, :duplicate)
    rescue StandardError => e
      failure_result(command, e.class.name.underscore)
    end

    def apply_assign(issue, command, commit_sha)
      return skipped_result(command, :no_username) if command.value.blank?

      user = User.find_by_login(command.value) || User.find_by_login(command.value.downcase)
      return skipped_result(command, :unknown_user) unless user

      marker_str = marker(commit_sha, :assign, issue.id, command.value)

      if duplicate_automation_event?(issue, marker_str, :assign)
        return skipped_result(command, :duplicate)
      end

      issue.init_journal(@user, build_note("Smart commit: Assigned to #{user.login} (commit #{commit_sha[0..7]})", marker_str))
      issue.assigned_to = user
      issue.save!

      create_automation_event(issue, marker_str, :assign)

      Result.new(
        issue_key: command.issue_key,
        action: :assign,
        status: :processed,
        message: "assigned_to:#{user.id}"
      )
    rescue ActiveRecord::RecordNotUnique
      skipped_result(command, :duplicate)
    rescue StandardError => e
      failure_result(command, e.class.name.underscore)
    end

    DURATION_PATTERN = /(\d+)\s*(h|m)/i

    def parse_duration(text)
      return nil if text.blank?

      total = 0.0
      text.strip.scan(DURATION_PATTERN) do |amount, unit|
        value = amount.to_f
        case unit.downcase
        when 'h'
          total += value
        when 'm'
          total += value / 60.0
        end
      end
      total > 0 ? total : nil
    rescue StandardError
      nil
    end

    def time_entry_activity
      TimeEntryActivity.shared.active.order(:position).first
    end

    def duplicate_automation_event?(issue, marker_str, action_type)
      ExternalAutomationEvent.exists?(
        issue_id: issue.id,
        marker: marker_str
      )
    end

    def create_automation_event(issue, marker_str, action_type)
      ExternalAutomationEvent.create!(
        issue_id: issue.id,
        marker: marker_str,
        action_type: action_type.to_s
      )
    end

    def build_note(note, marker_str)
      parts = ["[redmine-dev-integration:#{marker_str}]"]
      parts << note.to_s if note.present?
      parts.join("\n")
    end

    def skipped_result(command, reason)
      Result.new(
        issue_key: command.issue_key,
        action: command.action.to_s,
        status: :skipped,
        message: reason.to_s
      )
    end

    def failure_result(command, reason)
      Result.new(
        issue_key: command.issue_key,
        action: command.action.to_s,
        status: :failure,
        message: reason.to_s
      )
    end
  end
end
