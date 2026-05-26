# frozen_string_literal: true

module RedmineDevIntegration
  class RepositoryAuditService
    Result = Struct.new(:status, :line, :payload, :error, keyword_init: true) do
      def logged?
        status == :logged
      end

      def failed?
        status == :failed
      end
    end

    def call(action:, repository:, project:, actor: User.current)
      payload = build_payload(action: action, repository: repository, project: project, actor: actor)
      line = build_log_line(payload)

      Rails.logger.info(line)
      Result.new(status: :logged, line: line, payload: payload)
    rescue StandardError => e
      Result.new(status: :failed, payload: payload, error: e.message)
    end

    private

    def build_payload(action:, repository:, project:, actor:)
      {
        action: action.to_s,
        message: event_message(action),
        provider: repository.provider,
        full_name: repository.full_name,
        project_identifier: project.identifier,
        actor_login: actor&.login,
        redmine_repository_id: repository.redmine_repository_id
      }
    end

    def build_log_line(payload)
      parts = [
        "action=#{payload[:action]}",
        "message=#{payload[:message].inspect}",
        "provider=#{payload[:provider]}",
        "full_name=#{payload[:full_name].inspect}",
        "project=#{payload[:project_identifier].inspect}",
        "actor=#{payload[:actor_login].inspect}"
      ]
      parts << "redmine_repository_id=#{payload[:redmine_repository_id].inspect}" if payload[:redmine_repository_id].present?

      "redmine_dev_integration.repository_audit #{parts.join(' ')}"
    end

    def event_message(action)
      I18n.t("redmine_dev_integration.repository_audit.events.#{action}", default: action.to_s.tr('_', ' '))
    end
  end
end
