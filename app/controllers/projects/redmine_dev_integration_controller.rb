# frozen_string_literal: true

require 'json'

module Projects
  class RedmineDevIntegrationController < ApplicationController
    before_action :find_project
    before_action :authorize_manage_development_integration, except: %i[trigger_provider_sync retry_provider_event create_branch]
    before_action :authorize_retry_provider_event, only: :retry_provider_event
    before_action :authorize_trigger_provider_sync, only: :trigger_provider_sync
    before_action :authorize_register_webhook, only: :register_webhook
    before_action :authorize_create_branch, only: :create_branch
    before_action :find_external_repository, only: %i[edit update destroy trigger_provider_sync register_webhook]
    before_action :find_external_provider_event, only: :retry_provider_event

    def new
      @external_repository = @project.external_repositories.build(active: true)
    end

    def edit
    end

    def load_repositories
      provider = params[:provider].to_s.strip
      return render json: { error: t('redmine_dev_integration.load_repositories.provider_required') }, status: :bad_request if provider.blank?
      return render json: { error: t('redmine_dev_integration.load_repositories.unsupported_provider') }, status: :bad_request unless %w[github gitlab bitbucket].include?(provider)

      client = case provider
               when 'github'
                 RedmineDevIntegration::ProviderClients::GithubClient.new
               when 'gitlab'
                 RedmineDevIntegration::ProviderClients::GitlabClient.new
               when 'bitbucket'
                 RedmineDevIntegration::ProviderClients::BitbucketClient.new
               end

      return render json: { error: t('redmine_dev_integration.load_repositories.credentials_missing') }, status: :service_unavailable if client.credentials_missing?

      repos = client.list_repositories
      render json: { repositories: repos.map { |r| { id: r[:provider_repository_id], full_name: r[:full_name], url: r[:url] } } }
    end

    def settings
      setting = DevelopmentIntegrationProjectSetting.for_project(@project)

      if setting.update(development_integration_project_setting_params)
        flash[:notice] = l(:notice_successful_update)
        redirect_to settings_project_path(@project, tab: params[:tab] || 'dev_integration_settings')
      else
        flash[:alert] = setting.errors.full_messages.to_sentence
        redirect_to settings_project_path(@project, tab: params[:tab] || 'dev_integration_settings')
      end
    end

    def create
      validation_result = validate_external_repository
      @external_repository = @project.external_repositories.build(validation_result.normalized_attributes)
      @external_repository.repository_url_or_path = external_repository_params[:repository_url_or_path]

      if validation_result.valid?
        if @external_repository.save
          audit_repository(:connected, @external_repository)
          audit_repository(:scm_linked, @external_repository) if @external_repository.redmine_repository_id.present?
          attempt_auto_webhook_registration(@external_repository)
          flash[:notice] = l(:notice_successful_create)
          redirect_to settings_project_path(@project, tab: 'dev_integration_repos')
          return
        end
      end

      validation_result.errors.each { |e| @external_repository.errors.add(e.attribute, e.message) }
      render :new
    end

    def update
      validation_result = validate_external_repository(existing_repository: @external_repository)
      previous_redmine_repository_id = @external_repository.redmine_repository_id
      @external_repository.assign_attributes(validation_result.normalized_attributes)
      @external_repository.repository_url_or_path = external_repository_params[:repository_url_or_path]

      if validation_result.valid?
        if @external_repository.save
          audit_repository(:updated, @external_repository)
          audit_repository(:scm_linked, @external_repository) if previous_redmine_repository_id.blank? && @external_repository.redmine_repository_id.present?
          audit_repository(:scm_unlinked, @external_repository) if previous_redmine_repository_id.present? && @external_repository.redmine_repository_id.blank?
          if previous_redmine_repository_id.present? && @external_repository.redmine_repository_id.present? &&
              previous_redmine_repository_id != @external_repository.redmine_repository_id
            audit_repository(:scm_unlinked, @external_repository)
            audit_repository(:scm_linked, @external_repository)
          end
          flash[:notice] = l(:notice_successful_update)
          redirect_to settings_project_path(@project, tab: 'dev_integration_repos')
          return
        end
      end

      validation_result.errors.each { |e| @external_repository.errors.add(e.attribute, e.message) }
      render :edit
    end

    def destroy
      @external_repository.update!(active: false)
      audit_repository(:deactivated, @external_repository)
      flash[:notice] = l(:notice_successful_delete)
      redirect_to settings_project_path(@project, tab: 'dev_integration_repos')
    end

    def trigger_provider_sync
      result = RedmineDevIntegration::ReconciliationService.new.call(
        project: @project,
        repository: @external_repository,
        provider: @external_repository.provider
      )

      redirect_to settings_project_path(@project, tab: 'dev_integration_repos'),
                  notice: reconciliation_flash_message(result)
    end

    def register_webhook
      webhook_url = build_provider_webhook_url(@external_repository.provider)
      result = RedmineDevIntegration::WebhookRegistrationService.new.register(
        repository: @external_repository,
        redmine_webhook_url: webhook_url
      )

      if result.success?
        redirect_to settings_project_path(@project, tab: 'dev_integration_repos'),
                    notice: result.message
      else
        redirect_to settings_project_path(@project, tab: 'dev_integration_repos'),
                    alert: humanize_webhook_error(result.message, @external_repository)
      end
    end

    def retry_provider_event
      unless @external_provider_event.status == 'failed'
        redirect_to settings_project_path(@project, tab: 'dev_integration_events'),
                    alert: t('redmine_dev_integration.provider_events.retry_unavailable')
        return
      end

      if @external_provider_event.update(status: 'pending', processed_at: nil, error_message: nil)
        ExternalProviderEventJob.perform_later(@external_provider_event.id)
        redirect_to settings_project_path(@project, tab: 'dev_integration_events'),
                    notice: t('redmine_dev_integration.provider_events.retry_queued')
      else
        redirect_to settings_project_path(@project, tab: 'dev_integration_events'),
                    alert: @external_provider_event.errors.full_messages.to_sentence
      end
    end

    def create_user_mapping
      mapping = ExternalProviderUserMapping.create!(
        provider: params[:mapping_provider],
        provider_user_id: params[:mapping_provider_user_id],
        provider_login: params[:mapping_provider_login],
        user_id: params[:mapping_user_id]
      )
      flash[:notice] = l(:notice_successful_create)
      redirect_to settings_project_path(@project, tab: 'dev_integration_users')
    rescue ActiveRecord::RecordInvalid => e
      flash[:error] = e.message
      redirect_to settings_project_path(@project, tab: 'dev_integration_users')
    end

    def destroy_user_mapping
      mapping = ExternalProviderUserMapping.find(params[:mapping_id])
      mapping.destroy!
      flash[:notice] = l(:notice_successful_delete)
      redirect_to settings_project_path(@project, tab: 'dev_integration_users')
    end

    def create_branch
      @issue = Issue.visible.find(params[:issue_id])
      repository = @project.external_repositories.active.find(params[:repository_id])
      branch_name = generate_branch_name(@issue)
      redirect_url = repository.branch_url(branch_name)
      redirect_to redirect_url, allow_other_host: true, status: :see_other
    end

    def mark_deployment_failed
      deployment = ExternalDeployment.where(external_repository_id: @project.external_repositories.pluck(:id)).find(params[:deployment_id])
      deployment.update!(status: 'failed')
      flash[:notice] = l(:notice_successful_update)
      redirect_to project_deployment_overview_path(@project)
    end

    private

    def find_project
      @project = Project.find(params[:project_id])
    end

    def authorize_manage_development_integration
      render_403 unless User.current.allowed_to?(:manage_development_integration, @project)
    end

    def authorize_retry_provider_event
      allowed =
        User.current.allowed_to?(:manage_development_integration, @project) ||
        User.current.allowed_to?(:manage_provider_webhooks, @project)

      render_403 unless allowed
    end

    def authorize_trigger_provider_sync
      allowed =
        User.current.allowed_to?(:trigger_provider_sync, @project) ||
        User.current.allowed_to?(:manage_development_integration, @project)

      render_403 unless allowed
    end

    def authorize_create_branch
      render_403 unless User.current.allowed_to?(:view_development_integration, @project)
    end

    def authorize_register_webhook
      render_403 unless User.current.allowed_to?(:manage_provider_webhooks, @project)
    end

    def find_external_repository
      @external_repository = @project.external_repositories.find(params[:id])
    end

    def find_external_provider_event
      @external_provider_event = ExternalProviderEvent.find(params[:id])
      render_404 unless external_provider_event_for_project?(@external_provider_event)
    end

    def external_repository_params
      params.require(:external_repository).permit(
        :provider,
        :repository_url_or_path,
        :provider_repository_id,
        :owner,
        :repo_name,
        :full_name,
        :url,
        :redmine_repository_id,
        :active
      )
    end

    def validate_external_repository(existing_repository: nil)
      RedmineDevIntegration::ProviderRepositoryValidator.call(
        project: @project,
        attributes: external_repository_params,
        existing_repository: existing_repository
      )
    end

    def audit_repository(action, repository)
      RedmineDevIntegration::RepositoryAuditService.new.call(
        action: action,
        repository: repository,
        project: @project,
        actor: User.current
      )
    end

    def build_provider_webhook_url(provider)
      protocol = Setting.protocol
      host = Setting.host_name
      base = "#{protocol}://#{host}"

      case provider.to_s
      when 'github'
        "#{base}/dev_integrations/github/webhook"
      when 'gitlab'
        "#{base}/dev_integrations/gitlab/webhook"
      else
        ''
      end
    end

    def development_integration_project_setting_params
      params.require(:development_integration_project_setting).permit(
        :show_dev_panel,
        :automation_enabled,
        :auto_register_webhooks,
        :branch_created_status_id,
        :pr_opened_status_id,
        :pr_merged_status_id,
        :pr_closed_note_enabled,
        :show_builds,
        :show_deployments,
        :build_failed_note_enabled,
        :build_success_status_id,
        :deployment_staging_success_status_id,
        :deployment_production_success_status_id,
        :deployment_failed_note_enabled,
        :deployment_failed_status_id,
        :smart_commits_enabled
      )
    end

    def reconciliation_flash_message(result)
      if result.reconciled?
        t('redmine_dev_integration.reconciliation.reconciled', repository: @external_repository.full_name)
      else
        t(
          'redmine_dev_integration.reconciliation.skipped',
          repository: @external_repository.full_name,
          reason: t(
            "redmine_dev_integration.reconciliation.reasons.#{result.reason}",
            default: result.reason.to_s.tr('_', ' ')
          )
        )
      end
    end

    def external_provider_event_for_project?(event)
      return false if event.nil?

      repository_keys = @project.external_repositories.pluck(:provider, :provider_repository_id).map do |provider, repository_id|
        [provider.to_s, repository_id.to_s]
      end

      repository_key = external_provider_event_repository_key(event)
      repository_key.present? && repository_keys.include?(repository_key)
    end

    def external_provider_event_repository_key(event)
      payload = parse_event_payload(event.payload)
      return if payload.blank?

      repository_id =
        case event.provider.to_s
        when 'github'
          payload.dig('repository', 'id')
        when 'gitlab'
          payload.dig('project', 'id') || payload['project_id'] || payload.dig('repository', 'id') || payload.dig('object_attributes', 'target_project_id')
        end

      [event.provider.to_s, repository_id.to_s] if repository_id.present?
    end

    def attempt_auto_webhook_registration(repository)
      setting = DevelopmentIntegrationProjectSetting.for_project(@project)
      return unless setting.auto_register_webhooks?
      return unless User.current.allowed_to?(:manage_provider_webhooks, @project)

      webhook_url = build_provider_webhook_url(repository.provider)
      result = RedmineDevIntegration::WebhookRegistrationService.new.register(
        repository: repository,
        redmine_webhook_url: webhook_url
      )

      flash[:warning] = t('redmine_dev_integration.webhook_auto_register.failed', message: result.message) unless result.success?
    end

    def parse_event_payload(payload)
      return payload if payload.is_a?(Hash)
      return {} if payload.blank?

      JSON.parse(payload)
    rescue JSON::ParserError, TypeError
      nil
    end

    def humanize_webhook_error(raw_message, repository)
      t('redmine_dev_integration.webhook_register.rejected_by_api',
        provider: repository.provider.capitalize,
        repository: repository.full_name,
        raw_message: raw_message)
    end

    def generate_branch_name(issue)
      prefix = params[:prefix].presence || 'feature'
      slug = issue.subject.parameterize.first(40)
      key = issue.try(:issue_key) || issue.id.to_s
      "#{prefix}/#{key}-#{slug}"
    end
  end
end
