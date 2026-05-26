# frozen_string_literal: true

require_relative 'provider_clients/base_client'
require_relative 'provider_clients/github_client'
require_relative 'provider_clients/gitlab_client'
require_relative 'provider_clients/bitbucket_client'

module RedmineDevIntegration
  class ReconciliationService
    Result = Struct.new(:status, :reason, :repository, :provider, keyword_init: true) do
      def reconciled?
        status == :reconciled
      end

      def skipped?
        status == :skipped
      end

      def failed?
        status == :failed
      end
    end

    SUPPORTED_PROVIDERS = %w[github gitlab bitbucket].freeze

    def initialize(provider_client_factory: nil)
      @provider_client_factory = provider_client_factory
    end

    def call(project:, repository: nil, provider: nil)
      normalized_provider = normalize_provider(repository, provider)

      return skipped_result(:unsupported_provider, repository: repository, provider: normalized_provider) if unsupported_provider?(normalized_provider)
      return skipped_result(:api_polling_unsupported, provider: normalized_provider) unless repository
      return skipped_result(:project_mismatch, repository: repository, provider: normalized_provider) if repository.redmine_project_id != project.id
      return skipped_result(:inactive_repository, repository: repository, provider: normalized_provider) unless repository.active?

      client = provider_client_for(normalized_provider)
      return skipped_result(:credentials_missing, repository: repository, provider: normalized_provider) if credentials_missing?(client)

      reconcile_repository(repository: repository, provider: normalized_provider, client: client)
    rescue StandardError => e
      failed_result(:unexpected_error, repository: repository, provider: normalized_provider, error: e)
    end

    private

    attr_reader :provider_client_factory

    def reconcile_repository(repository:, provider:, client:)
      pull_requests = fetch_records(client, :recent_pull_requests, repository: repository)
      builds = fetch_records(client, :recent_builds, repository: repository)
      deployments = fetch_records(client, :recent_deployments, repository: repository)

      persist_reconciled_state(repository: repository, provider: provider, pull_requests: pull_requests, builds: builds, deployments: deployments)
    rescue StandardError => e
      failed_result(:api_failure, repository: repository, provider: provider, error: e)
    end

    def fetch_records(client, method_name, repository:)
      return [] unless client.respond_to?(method_name)

      Array(client.public_send(method_name, repository: repository))
    end

    def persist_reconciled_state(repository:, provider:, pull_requests:, builds:, deployments:)
      timestamp = Time.current

      ActiveRecord::Base.transaction do
        upsert_pull_requests(repository, provider, pull_requests)
        upsert_builds(repository, provider, builds)
        upsert_deployments(repository, provider, deployments)

        repository.update!(last_synced_at: timestamp)
      end

      Result.new(status: :reconciled, reason: :last_synced_at_updated, repository: repository.reload, provider: provider)
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
      failed_result(:save_failed, repository: repository, provider: provider, error: e)
    rescue StandardError => e
      failed_result(:save_failed, repository: repository, provider: provider, error: e)
    end

    def upsert_pull_requests(repository, provider, pull_requests)
      pull_requests.each do |record|
        attrs = normalize_record(record)
        number = attrs['number'].presence || attrs['id'].presence
        next if number.blank?

        pull_request = ExternalPullRequest.find_or_initialize_by(
          provider: provider,
          external_repository: repository,
          number: number.to_i
        )

        pull_request.title = attrs['title'].presence || "Pull request #{number}"
        pull_request.body = attrs['body']
        pull_request.url = attrs['url'].presence || attrs['html_url']
        pull_request.state = attrs['state'].presence || 'open'
        pull_request.author_login = attrs['author_login'] || attrs.dig('user', 'login')
        pull_request.source_branch = attrs['source_branch'] || attrs.dig('head', 'ref')
        pull_request.target_branch = attrs['target_branch'] || attrs.dig('base', 'ref')
        pull_request.merged = truthy?(attrs['merged'])
        pull_request.merged_at = parsed_time(attrs['merged_at'])
        pull_request.opened_at = parsed_time(attrs['opened_at'] || attrs['created_at'])
        pull_request.closed_at = parsed_time(attrs['closed_at'])
        pull_request.last_event_at = parsed_time(attrs['last_event_at'] || attrs['updated_at'] || attrs['created_at']) || Time.current

        pull_request.save!
        pull_request.link_issues_from_texts(
          pull_request.title,
          pull_request.body,
          pull_request.source_branch,
          pull_request.target_branch
        )
      end
    end

    def upsert_builds(repository, provider, builds)
      builds.each do |record|
        attrs = normalize_record(record)
        provider_build_id = attrs['provider_build_id'].presence || attrs['id'].presence
        next if provider_build_id.blank?

        build = ExternalBuild.find_or_initialize_by(
          provider: provider,
          external_repository: repository,
          provider_build_id: provider_build_id.to_s
        )

        build.build_number = attrs['build_number'].presence || attrs['number'].presence || attrs['run_number'].presence || provider_build_id
        build.name = attrs['name'].presence || attrs['display_title'].presence || "Build #{provider_build_id}"
        build.status = attrs['status'].presence || 'unknown'
        build.conclusion = attrs['conclusion']
        build.url = attrs['url'].presence || attrs['html_url']
        build.sha = attrs['sha'] || attrs['head_sha']
        build.ref = attrs['ref'] || attrs['branch_name']
        build.branch_name = attrs['branch_name'] || attrs['ref']
        build.author_login = attrs['author_login'] || attrs.dig('actor', 'login')
        build.started_at = parsed_time(attrs['started_at'] || attrs['run_started_at'] || attrs['created_at'])
        build.finished_at = parsed_time(attrs['finished_at'] || attrs['completed_at'])
        build.last_event_at = parsed_time(attrs['last_event_at'] || attrs['updated_at'] || attrs['created_at']) || Time.current

        build.save!
        build.link_issues_from_texts(
          build.name,
          build.branch_name,
          build.ref,
          build.conclusion
        )
      end
    end

    def upsert_deployments(repository, provider, deployments)
      deployments.each do |record|
        attrs = normalize_record(record)
        provider_deployment_id = attrs['provider_deployment_id'].presence || attrs['id'].presence
        next if provider_deployment_id.blank?

        environment_name = attrs['environment_name'].presence || attrs['environment'].presence || 'unknown'

        deployment = ExternalDeployment.find_or_initialize_by(
          provider: provider,
          external_repository: repository,
          provider_deployment_id: provider_deployment_id.to_s,
          environment_name: environment_name
        )

        deployment.environment_url = attrs['environment_url'] || attrs['target_url']
        deployment.status = attrs['status'].presence || 'unknown'
        deployment.sha = attrs['sha']
        deployment.ref = attrs['ref'] || attrs['branch_name']
        deployment.branch_name = attrs['branch_name'] || attrs['ref']
        deployment.description = attrs['description'] || attrs['commit_title']
        deployment.creator_login = attrs['creator_login'] || attrs.dig('creator', 'login') || attrs.dig('user', 'username')
        deployment.started_at = parsed_time(attrs['started_at'] || attrs['created_at'])
        deployment.completed_at = parsed_time(attrs['completed_at'] || attrs['finished_at'])
        deployment.last_event_at = parsed_time(attrs['last_event_at'] || attrs['updated_at'] || attrs['created_at']) || Time.current

        deployment.save!
        deployment.link_issues_from_texts(
          deployment.ref,
          deployment.branch_name,
          deployment.description,
          deployment.environment_url
        )
      end
    end

    def normalize_provider(repository, provider)
      provider.presence || repository&.provider
    end

    def unsupported_provider?(provider)
      provider.blank? || !SUPPORTED_PROVIDERS.include?(provider.to_s)
    end

    def provider_client_for(provider)
      return provider_client_factory.call(provider) if provider_client_factory.respond_to?(:call)

      case provider.to_s
      when 'github'
        ProviderClients::GitHubClient.new
      when 'gitlab'
        ProviderClients::GitLabClient.new
      when 'bitbucket'
        ProviderClients::BitbucketClient.new
      end
    end

    def credentials_missing?(client)
      client.respond_to?(:credentials_missing?) && client.credentials_missing?
    end

    def normalize_record(record)
      raw = record.respond_to?(:to_h) ? record.to_h : record
      raw = raw.stringify_keys if raw.respond_to?(:stringify_keys)
      raw.is_a?(Hash) ? raw : {}
    end

    def parsed_time(value)
      return if value.blank?
      return value.in_time_zone if value.respond_to?(:in_time_zone) && !value.is_a?(String)

      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def truthy?(value)
      value == true || value.to_s == '1' || value.to_s.casecmp('true').zero?
    end

    def skipped_result(reason, repository: nil, provider: nil)
      Result.new(status: :skipped, reason: reason.to_sym, repository: repository, provider: provider)
    end

    def failed_result(reason, repository: nil, provider: nil, error: nil)
      Result.new(status: :failed, reason: reason.to_sym, repository: repository, provider: provider)
    end
  end
end
