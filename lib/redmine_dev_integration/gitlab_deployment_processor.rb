# frozen_string_literal: true

require 'json'
require_relative 'provider_user_resolver'

module RedmineDevIntegration
  class GitlabDeploymentProcessor
    TERMINAL_STATUSES = %w[success failed canceled].freeze

    def initialize; end

    def call(external_provider_event)
      payload = parse_payload(external_provider_event.payload)
      return false unless payload.is_a?(Hash)
      return false unless external_provider_event.provider == 'gitlab'
      return false unless external_provider_event.event_type == 'Deployment Hook'

      repository = external_repository_for(payload)
      return false unless repository

      provider_deployment_id = (payload['deployment_id'] || payload['id']).to_s
      return false if provider_deployment_id.blank?

      environment_name = payload['environment'].presence || 'unknown'

      external_deployment = ExternalDeployment.find_or_initialize_by(
        provider: 'gitlab',
        external_repository: repository,
        provider_deployment_id: provider_deployment_id,
        environment_name: environment_name
      )

      raw_status = payload['status']
      external_deployment.environment_url = payload['environment_external_url']
      external_deployment.status = normalized_status(raw_status)
      external_deployment.sha = payload['sha']
      external_deployment.ref = payload['ref']
      external_deployment.branch_name = payload['ref']
      external_deployment.description = payload['commit_title'].presence || payload['status']
      external_deployment.creator_login = payload.dig('user', 'username').presence || payload.dig('user', 'name')
      external_deployment.started_at = time_value(payload['deployable_started_at'] || payload['created_at'])
      external_deployment.completed_at = time_value(payload['deployable_finished_at'] || payload['updated_at']) if terminal_status?(raw_status)
      external_deployment.last_event_at = time_value(payload['updated_at'] || payload['deployable_finished_at'])

      return false unless external_deployment.status.present?

      external_deployment.save!
      ExternalDeployment.detect_rollback(external_deployment)
      associate_release(external_deployment, payload)
      text_link_result = external_deployment.link_issues_from_texts(
        external_deployment.ref,
        external_deployment.branch_name,
        external_deployment.description,
        external_deployment.environment_url
      )
      link_traced_issues(external_deployment, trace_issues_for(external_deployment.external_repository, external_deployment.sha)) if text_link_result.issue_ids.empty?
      process_linked_issues(external_deployment, external_provider_event)
      handle_incidents(external_deployment, repository)
      true
    end

    private

    def parse_payload(payload)
      return payload if payload.is_a?(Hash)
      return {} if payload.blank?

      JSON.parse(payload)
    rescue JSON::ParserError
      nil
    end

    def external_repository_for(payload)
      RedmineDevIntegration::ExternalRepositoryResolver.gitlab(payload)
    end

    def normalized_status(status)
      case status.to_s
      when 'created', 'pending', 'blocked'
        'pending'
      when 'running'
        'in_progress'
      when 'success'
        'success'
      when 'failed'
        'failed'
      when 'canceled', 'cancelled'
        'canceled'
      else
        'unknown'
      end
    end

    def terminal_status?(status)
      TERMINAL_STATUSES.include?(normalized_status(status))
    end

    def time_value(value)
      return if value.blank?
      return value.in_time_zone if value.respond_to?(:in_time_zone) && !value.is_a?(String)

      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def process_linked_issues(external_deployment, external_provider_event)
      event_type = event_type_for(external_deployment)
      return unless event_type

      login = external_deployment.creator_login
      note = deployment_note(external_deployment, event_type)

      RedmineDevIntegration::ProviderUserResolver.with_resolved_user(
        provider: 'gitlab',
        provider_login: login
      ) do
        external_deployment.issues.find_each do |issue|
          AutomationService.new.call(
            issue: issue,
            event_type: event_type,
            project: external_deployment.external_repository.redmine_project,
            note: note,
            marker: automation_marker(external_deployment, event_type),
            external_provider_event: external_provider_event,
            environment_name: external_deployment.environment_name
          )
        end
      end
    end

    def trace_issues_for(external_repository, sha)
      RedmineDevIntegration::ShaIssueTracer.new.call(
        external_repository: external_repository,
        sha: sha
      )
    rescue StandardError
      []
    end

    def link_traced_issues(external_deployment, issue_ids)
      issue_ids.each do |issue_id|
        ExternalDeploymentIssue.find_or_create_by!(external_deployment_id: external_deployment.id, issue_id: issue_id)
      end
    end

    def event_type_for(external_deployment)
      case external_deployment.status
      when 'failed'
        'deployment_failed'
      when 'success'
        deployment_success_event_type(external_deployment.environment_name)
      end
    end

    def deployment_success_event_type(environment_name)
      case environment_name.to_s.downcase
      when 'staging'
        'deployment_staging_success'
      when 'production'
        'deployment_production_success'
      else
        'deployment_success'
      end
    end

    def deployment_note(external_deployment, event_type)
      return "Deployment failed: #{external_deployment.environment_name} | #{external_deployment.description}" if event_type == 'deployment_failed'

      nil
    end

    def automation_marker(external_deployment, event_type)
      "deployment:#{external_deployment.provider}:#{external_deployment.id}:#{event_type}"
    end

    def handle_incidents(external_deployment, repository)
      if external_deployment.status == 'failed'
        incident = ExternalIncident.find_or_create_by!(
          external_repository: repository,
          external_deployment: external_deployment,
          status: 'open'
        ) do |i|
          i.title = "Deployment failed: #{external_deployment.environment_name}"
          i.severity = external_deployment.environment_name == 'production' ? 'critical' : 'high'
          i.started_at = external_deployment.completed_at || Time.current
        end
        external_deployment.issues.each do |issue|
          ExternalIncidentIssue.find_or_create_by!(external_incident: incident, issue: issue)
        end
        DevIntegrationMailer.deliver_incident_created(incident) if incident.previous_changes.key?('id')
      elsif external_deployment.status == 'success'
        ExternalIncident.where(external_repository: repository, status: %w[open investigating])
          .update_all(status: 'resolved', resolved_at: external_deployment.completed_at || Time.current)
      end
    end

    def associate_release(deployment, payload)
      ref = payload['ref']
      return unless ref.present?

      tag_match = ref.match(%r{refs/tags/(.+)})
      return unless tag_match

      tag_name = tag_match[1]
      release = ExternalRelease.find_or_create_by!(
        provider: 'gitlab',
        external_repository: deployment.external_repository,
        name: tag_name
      ) do |r|
        r.tag_name = tag_name
        r.status = 'published'
        r.released_at = Time.current
      end

      deployment.update_column(:external_release_id, release.id)
      release.link_issues_from_deployments
    end
  end
end
