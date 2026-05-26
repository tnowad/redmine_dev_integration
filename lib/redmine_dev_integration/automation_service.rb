# frozen_string_literal: true

module RedmineDevIntegration
  class AutomationService
    Result = Struct.new(:status, :event_type, :action, :message, keyword_init: true) do
      def skipped?
        status == :skipped
      end

      def processed?
        status == :processed
      end

      def failure?
        status == :failure
      end
    end

    EVENT_ACTIONS = {
      'branch_created' => :set_branch_created_status,
      'pr_opened' => :set_pr_opened_status,
      'pr_merged' => :set_pr_merged_status,
      'pr_closed_without_merge' => :add_note,
      'build_failed' => :add_note,
      'build_success' => :set_build_success_status,
      'deployment_staging_success' => :set_deployment_staging_success_status,
      'deployment_production_success' => :set_deployment_production_success_status,
      'deployment_failed' => :set_deployment_failed_outcome,
      'deployment_success' => :set_deployment_success_status
    }.freeze

    def call(issue:, event_type:, project: nil, note: nil, marker: nil, external_provider_event: nil, external_provider_event_id: nil, environment_name: nil)
      existing_result = process_existing_mapping(issue, event_type, project, note, marker, external_provider_event, external_provider_event_id, environment_name)
      rules_result = process_automation_rules(issue, event_type, project, note, external_provider_event_id, environment_name)

      if existing_result&.processed?
        existing_result
      elsif rules_result&.processed?
        rules_result
      else
        rules_result || existing_result || skipped_result(event_type, :no_action)
      end
    end

    private

    def process_existing_mapping(issue, event_type, project, note, marker, external_provider_event, external_provider_event_id, environment_name)
      action = EVENT_ACTIONS[event_type.to_s]
      return skipped_result(event_type, :unknown_event) unless action
      return skipped_result(event_type, :disabled) unless enabled_for?(project)
      return skipped_result(event_type, :duplicate) if duplicate_marker?(issue, marker)

      automation_event_id = external_provider_event_id.presence || external_provider_event&.id

      case action
      when :set_branch_created_status
        apply_status_change(issue, event_type, project, action, note, marker, automation_event_id)
      when :set_pr_opened_status
        apply_status_change(issue, event_type, project, action, note, marker, automation_event_id)
      when :set_pr_merged_status
        apply_status_change(issue, event_type, project, action, note, marker, automation_event_id)
      when :set_build_success_status
        apply_status_change(issue, event_type, project, action, note, marker, automation_event_id)
      when :set_deployment_staging_success_status
        apply_status_change(issue, event_type, project, action, note, marker, automation_event_id)
      when :set_deployment_production_success_status
        apply_status_change(issue, event_type, project, action, note, marker, automation_event_id)
      when :set_deployment_success_status
        apply_deployment_success(issue, event_type, project, note, marker, automation_event_id, environment_name)
      when :set_deployment_failed_outcome
        apply_deployment_failed(issue, event_type, project, note, marker, automation_event_id, environment_name)
      when :add_note
        apply_note(issue, event_type, project, action, note, marker, automation_event_id)
      else
        skipped_result(event_type, :unsupported_action)
      end
    end

    def process_automation_rules(issue, event_type, project, note, external_provider_event_id, environment_name)
      return nil unless project

      rules = DevelopmentIntegrationAutomationRule.for_event(project, event_type, environment_name: environment_name)
      rules.reduce(nil) do |best, rule|
        result = execute_rule(rule, issue, note, external_provider_event_id)
        best = result if best.nil? || (result.processed? && !best.processed?)
        best
      end
    end

    def execute_rule(rule, issue, note, external_provider_event_id)
      marker = rule.dedup_marker(issue.id)
      return skipped_result(rule.event_type, :duplicate) if duplicate_marker?(issue, marker)

      case rule.action_type
      when 'assign_user'
        execute_assign_user(rule, issue, note, marker, external_provider_event_id)
      when 'set_priority'
        execute_set_priority(rule, issue, note, marker, external_provider_event_id)
      when 'set_custom_field'
        execute_set_custom_field(rule, issue, note, marker, external_provider_event_id)
      when 'change_status'
        execute_change_status(rule, issue, note, marker, external_provider_event_id)
      when 'add_note'
        execute_add_note(rule, issue, note, marker, external_provider_event_id)
      else
        skipped_result(rule.event_type, :unsupported_action)
      end
    rescue StandardError => e
      Rails.logger.error "AutomationService rule #{rule.id} (#{rule.action_type}) failed: #{e.class} #{e.message}"
      failure_result(rule.event_type, e.class.name.underscore)
    end

    def execute_assign_user(rule, issue, note, marker, external_provider_event_id)
      user = User.find_by(login: rule.action_value.to_s.strip)
      return failure_result(rule.event_type, :user_not_found) unless user

      persist_automation_event(issue, rule.event_type, rule.action_type, marker, external_provider_event_id) do
        issue.init_journal(current_journal_user, build_note(note, marker))
        issue.assigned_to_id = user.id

        if issue.save(validate: false)
          Result.new(status: :processed, event_type: rule.event_type, action: rule.action_type, message: "assigned_user:#{user.id}")
        else
          failure_result(rule.event_type, issue.errors.full_messages.to_sentence.presence || 'save_failed')
        end
      end
    rescue ActiveRecord::RecordNotUnique
      skipped_result(rule.event_type, :duplicate)
    end

    def execute_set_priority(rule, issue, note, marker, external_provider_event_id)
      priority = IssuePriority.find_by(name: rule.action_value.to_s.strip)
      return failure_result(rule.event_type, :priority_not_found) unless priority

      persist_automation_event(issue, rule.event_type, rule.action_type, marker, external_provider_event_id) do
        issue.init_journal(current_journal_user, build_note(note, marker))
        issue.priority = priority

        if issue.save
          Result.new(status: :processed, event_type: rule.event_type, action: rule.action_type, message: "set_priority:#{priority.id}")
        else
          failure_result(rule.event_type, issue.errors.full_messages.to_sentence.presence || 'save_failed')
        end
      end
    rescue ActiveRecord::RecordNotUnique
      skipped_result(rule.event_type, :duplicate)
    end

    def execute_set_custom_field(rule, issue, note, marker, external_provider_event_id)
      parts = rule.action_value.to_s.split(':', 2)
      field_id = parts[0].to_i
      value = parts[1].to_s

      return failure_result(rule.event_type, :invalid_custom_field_value) if field_id.zero? || value.empty?

      field = CustomField.find_by(id: field_id)
      return failure_result(rule.event_type, :custom_field_not_found) unless field
      return failure_result(rule.event_type, :not_issue_custom_field) unless field.is_a?(IssueCustomField)

      persist_automation_event(issue, rule.event_type, rule.action_type, marker, external_provider_event_id) do
        issue.init_journal(current_journal_user, build_note(note, marker))
        issue.custom_field_values = {field.id.to_s => value}

        if issue.save
          Result.new(status: :processed, event_type: rule.event_type, action: rule.action_type, message: "set_custom_field:#{field.id}")
        else
          failure_result(rule.event_type, issue.errors.full_messages.to_sentence.presence || 'save_failed')
        end
      end
    rescue ActiveRecord::RecordNotUnique
      skipped_result(rule.event_type, :duplicate)
    end

    def execute_change_status(rule, issue, note, marker, external_provider_event_id)
      status = IssueStatus.find_by(name: rule.action_value.to_s.strip)
      return failure_result(rule.event_type, :status_not_found) unless status

      persist_automation_event(issue, rule.event_type, rule.action_type, marker, external_provider_event_id) do
        issue.init_journal(current_journal_user, build_note(note, marker))
        issue.status = status

        if issue.save
          Result.new(status: :processed, event_type: rule.event_type, action: rule.action_type, message: "updated_status:#{status.id}")
        else
          failure_result(rule.event_type, issue.errors.full_messages.to_sentence.presence || 'save_failed')
        end
      end
    rescue ActiveRecord::RecordNotUnique
      skipped_result(rule.event_type, :duplicate)
    end

    def execute_add_note(rule, issue, note, marker, external_provider_event_id)
      note_text = note.presence || rule.action_value
      return skipped_result(rule.event_type, :missing_note) if note_text.blank?

      persist_automation_event(issue, rule.event_type, rule.action_type, marker, external_provider_event_id) do
        issue.init_journal(current_journal_user, build_note(note_text, marker))
        if issue.save
          Result.new(status: :processed, event_type: rule.event_type, action: rule.action_type, message: 'added_note')
        else
          failure_result(rule.event_type, issue.errors.full_messages.to_sentence.presence || 'save_failed')
        end
      end
    rescue ActiveRecord::RecordNotUnique
      skipped_result(rule.event_type, :duplicate)
    end

    def enabled_for?(project)
      project_setting = project_setting(project)
      return false unless project_setting

      project_setting.automation_enabled == true
    end

    def project_setting(project)
      return nil unless project&.respond_to?(:development_integration_project_setting)

      project.development_integration_project_setting || DevelopmentIntegrationProjectSetting.for_project(project)
    rescue StandardError
      nil
    end

    def status_id_for(event_type, project)
      setting = project_setting(project)
      return nil unless setting

      case event_type.to_s
      when 'branch_created'
        setting.branch_created_status_id
      when 'pr_opened'
        setting.pr_opened_status_id
      when 'pr_merged'
        setting.pr_merged_status_id
      when 'build_success'
        setting.build_success_status_id
      when 'deployment_staging_success'
        setting.deployment_staging_success_status_id
      when 'deployment_production_success'
        setting.deployment_production_success_status_id
      when 'deployment_failed'
        setting.deployment_failed_status_id
      end
    end

    def apply_status_change(issue, event_type, project, action, note, marker, external_provider_event_id)
      status_id = status_id_for(event_type, project)
      return skipped_result(event_type, :missing_mapping) unless status_id

      status = IssueStatus.find_by(id: status_id)
      return skipped_result(event_type, :missing_status) unless status

      persist_automation_event(issue, event_type, action, marker, external_provider_event_id) do
        issue.init_journal(current_journal_user, build_note(note, marker))
        issue.status = status

        if issue.save
          Result.new(status: :processed, event_type: event_type.to_s, action: action.to_s, message: "updated_status:#{status.id}")
        else
          failure_result(event_type, issue.errors.full_messages.to_sentence.presence || 'save_failed')
        end
      end
    rescue ActiveRecord::RecordNotUnique
      skipped_result(event_type, :duplicate)
    rescue StandardError => e
      failure_result(event_type, e.class.name.underscore)
    end

    def apply_note(issue, event_type, project, action, note, marker, external_provider_event_id)
      return skipped_result(event_type, :disabled) unless note_enabled_for?(event_type, project)
      return skipped_result(event_type, :missing_note) if note.blank?

      persist_automation_event(issue, event_type, action, marker, external_provider_event_id) do
        issue.init_journal(current_journal_user, build_note(note, marker))
        if issue.save
          Result.new(status: :processed, event_type: event_type.to_s, action: action.to_s, message: 'added_note')
        else
          failure_result(event_type, issue.errors.full_messages.to_sentence.presence || 'save_failed')
        end
      end
    rescue ActiveRecord::RecordNotUnique
      skipped_result(event_type, :duplicate)
    rescue StandardError => e
      failure_result(event_type, e.class.name.underscore)
    end

    def apply_deployment_failed(issue, event_type, project, note, marker, external_provider_event_id, environment_name = nil)
      rule = environment_name.present? ? environment_rule_for(project, environment_name) : nil

      if rule
        status_id = rule.failed_status_id
        note_enabled = rule.failed_note_enabled == true
        if status_id.blank? && !note_enabled
          return skipped_result(event_type, :missing_mapping)
        end
      else
        setting = project_setting(project)
        return skipped_result(event_type, :disabled) unless setting

        status_id = setting.deployment_failed_status_id
        note_enabled = setting.deployment_failed_note_enabled == true
      end

      if status_id.present?
        status = IssueStatus.find_by(id: status_id)
        return skipped_result(event_type, :missing_status) unless status

        persist_automation_event(issue, event_type, :set_deployment_failed_outcome, marker, external_provider_event_id) do
          issue.init_journal(current_journal_user, build_note(note_enabled ? note : nil, marker))
          issue.status = status

          if issue.save
            Result.new(status: :processed, event_type: event_type.to_s, action: 'set_deployment_failed_outcome', message: "updated_status:#{status.id}")
          else
            failure_result(event_type, issue.errors.full_messages.to_sentence.presence || 'save_failed')
          end
        end
      elsif note_enabled
        if rule
          apply_note_direct(issue, event_type, :add_note, note, marker, external_provider_event_id)
        else
          apply_note(issue, event_type, project, :add_note, note, marker, external_provider_event_id)
        end
      else
        skipped_result(event_type, :missing_mapping)
      end
    rescue ActiveRecord::RecordNotUnique
      skipped_result(event_type, :duplicate)
    rescue StandardError => e
      failure_result(event_type, e.class.name.underscore)
    end

    def apply_note_direct(issue, event_type, action, note, marker, external_provider_event_id)
      return skipped_result(event_type, :missing_note) if note.blank?

      persist_automation_event(issue, event_type, action, marker, external_provider_event_id) do
        issue.init_journal(current_journal_user, build_note(note, marker))
        if issue.save
          Result.new(status: :processed, event_type: event_type.to_s, action: action.to_s, message: 'added_note')
        else
          failure_result(event_type, issue.errors.full_messages.to_sentence.presence || 'save_failed')
        end
      end
    rescue ActiveRecord::RecordNotUnique
      skipped_result(event_type, :duplicate)
    rescue StandardError => e
      failure_result(event_type, e.class.name.underscore)
    end

    def note_enabled_for?(event_type, project)
      setting = project_setting(project)
      return false unless setting

      case event_type.to_s
      when 'pr_closed_without_merge'
        setting.pr_closed_note_enabled == true
      when 'build_failed'
        setting.build_failed_note_enabled == true
      when 'deployment_failed'
        setting.deployment_failed_note_enabled == true
      else
        false
      end
    end

    def apply_deployment_success(issue, event_type, project, note, marker, automation_event_id, environment_name)
      rule = environment_rule_for(project, environment_name)

      if rule && rule.success_status_id.present?
        apply_deployment_status_change(issue, event_type, :set_deployment_success_status, note, marker, automation_event_id, rule.success_status_id)
      else
        status_id = legacy_deployment_status_id(project, environment_name)
        return skipped_result(event_type, :missing_mapping) unless status_id
        apply_deployment_status_change(issue, event_type, :set_deployment_success_status, note, marker, automation_event_id, status_id)
      end
    end

    def apply_deployment_status_change(issue, event_type, action, note, marker, external_provider_event_id, status_id)
      status = IssueStatus.find_by(id: status_id)
      return skipped_result(event_type, :missing_status) unless status

      persist_automation_event(issue, event_type, action, marker, external_provider_event_id) do
        issue.init_journal(current_journal_user, build_note(note, marker))
        issue.status = status

        if issue.save
          Result.new(status: :processed, event_type: event_type.to_s, action: action.to_s, message: "updated_status:#{status.id}")
        else
          failure_result(event_type, issue.errors.full_messages.to_sentence.presence || 'save_failed')
        end
      end
    rescue ActiveRecord::RecordNotUnique
      skipped_result(event_type, :duplicate)
    rescue StandardError => e
      failure_result(event_type, e.class.name.underscore)
    end

    def environment_rule_for(project, environment_name)
      return nil unless project && environment_name.present?

      DevelopmentIntegrationEnvironmentRule.for_project_and_environment(project, environment_name.to_s.strip)
    end

    def legacy_deployment_status_id(project, environment_name)
      setting = project_setting(project)
      return nil unless setting

      case environment_name.to_s.downcase.strip
      when 'staging'
        setting.deployment_staging_success_status_id
      when 'production'
        setting.deployment_production_success_status_id
      end
    end

    def current_journal_user
      User.current
    end

    def duplicate_marker?(issue, marker)
      return false if marker.blank?

      ExternalAutomationEvent.exists?(issue_id: issue.id, marker: marker)
    end

    def build_note(note, marker)
      return note if marker.blank?

      parts = [marker_token(marker)]
      parts << note.to_s if note.present?
      parts.join("\n")
    end

    def marker_token(marker)
      "[redmine-dev-integration:#{marker}]"
    end

    def failure_result(event_type, reason)
      Result.new(status: :failure, event_type: event_type.to_s, action: nil, message: reason.to_s)
    end

    def persist_automation_event(issue, event_type, action, marker, external_provider_event_id)
      result = nil

      issue.class.transaction do
        if marker.present?
          ExternalAutomationEvent.create!(
            issue_id: issue.id,
            external_provider_event_id: external_provider_event_id,
            marker: marker.to_s,
            action_type: action.to_s
          )
        end

        result = yield
        raise ActiveRecord::Rollback if result.failure?
      end

      result
    end

    def skipped_result(event_type, reason)
      Result.new(status: :skipped, event_type: event_type.to_s, action: nil, message: reason.to_s)
    end
  end
end
