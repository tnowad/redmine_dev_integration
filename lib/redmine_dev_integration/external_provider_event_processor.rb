# frozen_string_literal: true

require_relative 'github_push_branch_processor'
require_relative 'github_pull_request_processor'
require_relative 'github_workflow_run_processor'
require_relative 'github_deployment_status_processor'
require_relative 'gitlab_push_branch_processor'
require_relative 'gitlab_merge_request_processor'
require_relative 'gitlab_pipeline_processor'
require_relative 'gitlab_deployment_processor'
require_relative 'bitbucket_push_branch_processor'
require_relative 'bitbucket_pull_request_processor'
require_relative 'bitbucket_pipeline_processor'
require_relative 'bitbucket_deployment_processor'
require_relative 'provider_event_logger'

module RedmineDevIntegration
  class ExternalProviderEventProcessor
    def self.call(external_provider_event)
      new.call(external_provider_event)
    end

    def call(external_provider_event)
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      status = external_provider_event.status
      error = nil

      external_provider_event.with_lock do
        return external_provider_event if already_finalized?(external_provider_event)

        process_event(external_provider_event)
        status = external_provider_event.status
      end

      external_provider_event
    rescue StandardError => e
      error = e
      status = 'failed'
      mark_failed(external_provider_event, e)
      external_provider_event
    ensure
      log_provider_event(external_provider_event, status: status, started_at: started_at, error: error)
    end

    private

    def github_push_branch_processor
      @github_push_branch_processor ||= GitHubPushBranchProcessor.new
    end

    def github_pull_request_processor
      @github_pull_request_processor ||= GitHubPullRequestProcessor.new
    end

    def github_workflow_run_processor
      @github_workflow_run_processor ||= GitHubWorkflowRunProcessor.new
    end

    def github_deployment_status_processor
      @github_deployment_status_processor ||= GitHubDeploymentStatusProcessor.new
    end

    def gitlab_push_branch_processor
      @gitlab_push_branch_processor ||= GitlabPushBranchProcessor.new
    end

    def gitlab_merge_request_processor
      @gitlab_merge_request_processor ||= GitlabMergeRequestProcessor.new
    end

    def gitlab_pipeline_processor
      @gitlab_pipeline_processor ||= GitlabPipelineProcessor.new
    end

    def gitlab_deployment_processor
      @gitlab_deployment_processor ||= GitlabDeploymentProcessor.new
    end

    def bitbucket_push_branch_processor
      @bitbucket_push_branch_processor ||= BitbucketPushBranchProcessor.new
    end

    def bitbucket_pull_request_processor
      @bitbucket_pull_request_processor ||= BitbucketPullRequestProcessor.new
    end

    def bitbucket_pipeline_processor
      @bitbucket_pipeline_processor ||= BitbucketPipelineProcessor.new
    end

    def bitbucket_deployment_processor
      @bitbucket_deployment_processor ||= BitbucketDeploymentProcessor.new
    end

    def already_finalized?(external_provider_event)
      %w[processed ignored].include?(external_provider_event.status)
    end

    def process_event(external_provider_event)
      handled = case external_provider_event.provider
                when 'github'
                  github_push_branch_processor.call(external_provider_event) ||
                    github_pull_request_processor.call(external_provider_event) ||
                    github_workflow_run_processor.call(external_provider_event) ||
                    github_deployment_status_processor.call(external_provider_event)
                when 'gitlab'
                  gitlab_push_branch_processor.call(external_provider_event) ||
                    gitlab_merge_request_processor.call(external_provider_event) ||
                    gitlab_pipeline_processor.call(external_provider_event) ||
                    gitlab_deployment_processor.call(external_provider_event)
                when 'bitbucket'
                  bitbucket_push_branch_processor.call(external_provider_event) ||
                    bitbucket_pull_request_processor.call(external_provider_event) ||
                    bitbucket_pipeline_processor.call(external_provider_event) ||
                    bitbucket_deployment_processor.call(external_provider_event)
                else
                  false
                end

      external_provider_event.processed_at = Time.current
      external_provider_event.status = handled ? 'processed' : 'ignored'
      external_provider_event.error_message = nil
      external_provider_event.save!
    end

    def mark_failed(external_provider_event, error)
      external_provider_event.status = 'failed'
      external_provider_event.processed_at = Time.current
      external_provider_event.error_message = "#{error.class}: #{error.message}"
      external_provider_event.save!(validate: false)
    end

    def provider_event_logger
      @provider_event_logger ||= ProviderEventLogger.new
    end

    def log_provider_event(external_provider_event, status:, started_at:, error:)
      provider_event_logger.call(
        external_provider_event,
        status: status,
        duration_ms: duration_ms(started_at),
        error: error
      )
    rescue StandardError
      nil
    end

    def duration_ms(started_at)
      ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
    end
  end
end
