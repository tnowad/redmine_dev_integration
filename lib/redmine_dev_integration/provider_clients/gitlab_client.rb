# frozen_string_literal: true

module RedmineDevIntegration
  module ProviderClients
    class GitLabClient < BaseClient
      def credentials_missing?
        api_token.blank? && oauth_access_token.blank?
      end

      def recent_pull_requests(repository:)
        paginated_get(api_uri("/projects/#{repository.provider_repository_id}/merge_requests?scope=all&order_by=updated_at&sort=desc&per_page=100"), headers: auth_headers).map do |merge_request|
          normalize_pull_request(merge_request)
        end
      end

      def recent_builds(repository:)
        paginated_get(api_uri("/projects/#{repository.provider_repository_id}/pipelines?order_by=updated_at&sort=desc&per_page=100"), headers: auth_headers).map do |pipeline|
          normalize_build(pipeline)
        end
      end

      def recent_deployments(repository:)
        paginated_get(api_uri("/projects/#{repository.provider_repository_id}/deployments?order_by=updated_at&sort=desc&per_page=100"), headers: auth_headers).map do |deployment|
          normalize_deployment(deployment)
        end
      end

      def repository_lookup(repository_path)
        require 'erb' unless defined?(ERB)
        encoded_path = ERB::Util.url_encode(repository_path)
        payload = fetch_json(api_uri("/projects/#{encoded_path}"), headers: auth_headers)
        normalize_repository_data(payload)
      rescue Net::HTTPNotFound
        raise RepositoryNotFoundError, "Repository '#{repository_path}' not found on GitLab"
      rescue Net::HTTPUnauthorized, Net::HTTPForbidden
        raise AuthenticationError, "GitLab API authentication failed"
      end

      def list_repositories
        repos = paginated_get(api_uri('/projects?membership=true&order_by=updated_at&per_page=100'), headers: auth_headers, max_pages: 3)
        repos.map { |r| normalize_repository_data(r) }
      rescue StandardError
        []
      end

      def list_webhooks(repository:)
        compact_collection(fetch_json(api_uri("/projects/#{repository.provider_repository_id}/hooks"), headers: auth_headers))
      end

      def create_webhook(repository:, url:, token:)
        body = {
          url: url,
          token: token,
          push_events: true,
          merge_requests_events: true,
          pipeline_events: true,
          deployment_events: true,
          enable_ssl_verification: true
        }
        post_json(api_uri("/projects/#{repository.provider_repository_id}/hooks"), body: body, headers: auth_headers)
      end

      def update_webhook(repository:, webhook_id:, url:, token:)
        body = {
          url: url,
          token: token,
          push_events: true,
          merge_requests_events: true,
          pipeline_events: true,
          deployment_events: true
        }
        put_json(api_uri("/projects/#{repository.provider_repository_id}/hooks/#{webhook_id}"), body: body, headers: auth_headers)
      end

      private

      def api_token
        oauth_token = oauth_access_token
        return oauth_token if oauth_token.present?

        setting_value('gitlab_api_token', 'gitlab_access_token', 'gitlab_private_token', 'gitlab_token')
      end

      def oauth_access_token
        return nil unless defined?(RedmineDevIntegration::Oauth::TokenStore)
        RedmineDevIntegration::Oauth::TokenStore.access_token('gitlab')
      end

      def auth_headers
        if oauth_access_token.present?
          { 'Authorization' => "Bearer #{api_token}", 'Accept' => 'application/json' }
        else
          { 'PRIVATE-TOKEN' => api_token, 'Accept' => 'application/json' }
        end
      end

      def api_uri(path)
        base = setting_value('gitlab_api_base_url', 'gitlab_base_url').presence || 'https://gitlab.com/api/v4'
        URI.join(base.end_with?('/') ? base : "#{base}/", path.sub(%r{\A/}, ''))
      end

      def normalize_pull_request(merge_request)
        merge_request = normalize_hash(merge_request)
        {
          number: merge_request['iid'],
          title: merge_request['title'],
          body: merge_request['description'] || merge_request['body'],
          url: merge_request['web_url'] || merge_request['url'],
          state: normalize_state(merge_request['state']),
          author_login: merge_request.dig('author', 'username'),
          source_branch: merge_request['source_branch'],
          target_branch: merge_request['target_branch'],
          merged: truthy?(merge_request['merged']),
          merged_at: parse_time(merge_request['merged_at']),
          opened_at: parse_time(merge_request['created_at']),
          closed_at: parse_time(merge_request['closed_at']),
          last_event_at: parse_time(merge_request['updated_at'] || merge_request['created_at'])
        }
      end

      def normalize_build(pipeline)
        pipeline = normalize_hash(pipeline)
        {
          provider_build_id: pipeline['id'],
          build_number: pipeline['iid'].presence || pipeline['id'],
          name: pipeline['name'].presence || "Pipeline #{pipeline['id']}",
          status: normalize_pipeline_status(pipeline['status']),
          conclusion: pipeline['status'],
          url: pipeline['web_url'] || pipeline['url'],
          sha: pipeline['sha'],
          ref: pipeline['ref'],
          branch_name: pipeline['ref'],
          author_login: pipeline.dig('user', 'username') || pipeline.dig('user', 'name'),
          started_at: parse_time(pipeline['created_at']),
          finished_at: parse_time(pipeline['finished_at']),
          last_event_at: parse_time(pipeline['updated_at'] || pipeline['finished_at'] || pipeline['created_at'])
        }
      end

      def normalize_deployment(deployment)
        deployment = normalize_hash(deployment)
        environment = deployment['environment']
        environment_name =
          case environment
          when Hash
            environment['name']
          else
            environment
          end

        deployable = deployment['deployable'].is_a?(Hash) ? deployment['deployable'] : {}

        {
          provider_deployment_id: deployment['id'],
          environment_name: environment_name.presence || 'unknown',
          environment_url: deployment['environment_url'] || (environment.is_a?(Hash) ? environment['external_url'] : nil),
          status: normalize_deployment_status(deployment['status']),
          sha: deployment['sha'],
          ref: deployment['ref'] || deployable['ref'],
          branch_name: deployment['ref'] || deployable['ref'],
          description: deployment['description'] || deployable['status'],
          creator_login: deployment.dig('user', 'username') || deployment.dig('user', 'name'),
          started_at: parse_time(deployment['created_at']),
          completed_at: parse_time(deployment['finished_at']),
          last_event_at: parse_time(deployment['updated_at'] || deployment['finished_at'] || deployment['created_at'])
        }
      end

      def normalize_state(state)
        case state.to_s
        when 'opened' then 'open'
        when 'closed', 'merged' then 'closed'
        else 'open'
        end
      end

      def normalize_pipeline_status(status)
        case status.to_s
        when 'created', 'pending'
          'queued'
        when 'running'
          'in_progress'
        when 'success'
          'success'
        when 'failed'
          'failed'
        when 'canceled', 'cancelled'
          'canceled'
        when 'skipped'
          'skipped'
        else
          'unknown'
        end
      end

      def normalize_deployment_status(status)
        case status.to_s
        when 'success'
          'success'
        when 'failed'
          'failed'
        when 'canceled', 'cancelled'
          'canceled'
        when 'running'
          'in_progress'
        when 'pending', 'created', 'blocked'
          'pending'
        else
          'unknown'
        end
      end

      def normalize_repository_data(payload)
        payload = normalize_hash(payload)
        namespace = payload['namespace']
        owner = if namespace.is_a?(Hash)
                  namespace['full_path'] || namespace['path'] || ''
                else
                  ''
                end
        {
          provider_repository_id: payload['id'].to_s,
          owner: owner,
          repo_name: payload['path'] || payload['name'] || '',
          full_name: payload['path_with_namespace'] || payload['full_path'] || '',
          url: payload['web_url'] || payload['http_url_to_repo'] || '',
          description: payload['description']
        }
      end
    end
  end
end
