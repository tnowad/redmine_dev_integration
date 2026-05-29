# frozen_string_literal: true

module RedmineDevIntegration
  module ProviderClients
    class GithubClient < BaseClient
      def credentials_missing?
        api_token.blank? && oauth_access_token.blank?
      end

      def recent_pull_requests(repository:)
        paginated_get(api_uri("/repos/#{repository.full_name}/pulls?state=all&sort=updated&direction=desc&per_page=100"), headers: auth_headers).map do |pull_request|
          normalize_pull_request(pull_request)
        end
      end

      def recent_builds(repository:)
        paginated_get(api_uri("/repos/#{repository.full_name}/actions/runs?per_page=100"), headers: auth_headers, collection_key: 'workflow_runs').map do |workflow_run|
          normalize_build(workflow_run)
        end
      end

      def recent_deployments(repository:)
        paginated_get(api_uri("/repos/#{repository.full_name}/deployments?per_page=100"), headers: auth_headers).map do |deployment|
          latest_status = latest_deployment_status(repository, deployment['id'])
          normalize_deployment(deployment, latest_status)
        end
      end

      def repository_lookup(repository_path)
        payload = fetch_json(api_uri("/repos/#{repository_path}"), headers: auth_headers)
        normalize_repository_data(payload)
      rescue Net::HTTPNotFound
        raise RepositoryNotFoundError, "Repository '#{repository_path}' not found on Github"
      rescue Net::HTTPUnauthorized, Net::HTTPForbidden
        raise AuthenticationError, "Github API authentication failed"
      end

      def list_repositories
        repos = paginated_get(api_uri('/user/repos?sort=updated&per_page=100'), headers: auth_headers, max_pages: 3)
        repos.map { |r| normalize_repository_data(r) }
      rescue StandardError
        []
      end

      def list_webhooks(repository:)
        compact_collection(fetch_json(api_uri("/repos/#{repository.full_name}/hooks"), headers: auth_headers))
      end

      def create_webhook(repository:, url:, secret:)
        body = {
          name: 'web',
          active: true,
          events: %w[push pull_request workflow_run deployment_status],
          config: { url: url, content_type: 'json', secret: secret }
        }
        post_json(api_uri("/repos/#{repository.full_name}/hooks"), body: body, headers: auth_headers)
      end

      def update_webhook(repository:, webhook_id:, url:, secret:)
        body = {
          active: true,
          events: %w[push pull_request workflow_run deployment_status],
          config: { url: url, content_type: 'json', secret: secret }
        }
        patch_json(api_uri("/repos/#{repository.full_name}/hooks/#{webhook_id}"), body: body, headers: auth_headers)
      end

      private

      def api_token
        oauth_token = oauth_access_token
        return oauth_token if oauth_token.present?

        setting_value('github_api_token', 'github_access_token', 'github_token')
      end

      def oauth_access_token
        return nil unless defined?(RedmineDevIntegration::Oauth::TokenStore)
        RedmineDevIntegration::Oauth::TokenStore.access_token('github')
      end

      def auth_headers
        {
          'Accept' => 'application/vnd.github+json',
          'Authorization' => "Bearer #{api_token}"
        }
      end

      def api_uri(path)
        base = setting_value('github_api_base_url', 'github_base_url').presence || 'https://api.github.com'
        URI.join(base.end_with?('/') ? base : "#{base}/", path.sub(%r{\A/}, ''))
      end

      def latest_deployment_status(repository, deployment_id)
        return {} if deployment_id.blank?

        payload = fetch_json(api_uri("/repos/#{repository.full_name}/deployments/#{deployment_id}/statuses?per_page=1"), headers: auth_headers)
        compact_collection(payload).first || {}
      rescue StandardError
        {}
      end

      def normalize_pull_request(pull_request)
        pull_request = normalize_hash(pull_request)
        {
          number: pull_request['number'],
          title: pull_request['title'],
          body: pull_request['body'],
          url: pull_request['html_url'],
          state: pull_request['state'],
          author_login: pull_request.dig('user', 'login'),
          source_branch: pull_request.dig('head', 'ref'),
          target_branch: pull_request.dig('base', 'ref'),
          merged: truthy?(pull_request['merged']),
          merged_at: parse_time(pull_request['merged_at']),
          opened_at: parse_time(pull_request['created_at']),
          closed_at: parse_time(pull_request['closed_at']),
          last_event_at: parse_time(pull_request['updated_at'] || pull_request['created_at'])
        }
      end

      def normalize_build(workflow_run)
        workflow_run = normalize_hash(workflow_run)
        {
          provider_build_id: workflow_run['id'],
          build_number: workflow_run['run_number'],
          name: workflow_run['display_title'].presence || workflow_run['name'],
          status: normalize_status(workflow_run['status'], workflow_run['conclusion']),
          conclusion: workflow_run['conclusion'],
          url: workflow_run['html_url'],
          sha: workflow_run['head_sha'],
          ref: workflow_run['head_branch'],
          branch_name: workflow_run['head_branch'],
          author_login: workflow_run.dig('actor', 'login'),
          started_at: parse_time(workflow_run['run_started_at'] || workflow_run['created_at']),
          finished_at: workflow_run['status'].to_s == 'completed' ? parse_time(workflow_run['updated_at']) : nil,
          last_event_at: parse_time(workflow_run['updated_at'] || workflow_run['created_at'])
        }
      end

      def normalize_deployment(deployment, status_payload)
        deployment = normalize_hash(deployment)
        status_payload = normalize_hash(status_payload)
        {
          provider_deployment_id: deployment['id'],
          environment_name: deployment['environment'].presence || status_payload['environment'].presence || 'unknown',
          environment_url: status_payload['environment_url'].presence || status_payload['target_url'],
          status: normalize_status(status_payload['state'], nil),
          sha: deployment['sha'],
          ref: deployment['ref'],
          branch_name: deployment['ref'],
          description: status_payload['description'].presence || deployment['description'],
          creator_login: status_payload.dig('creator', 'login').presence || deployment.dig('creator', 'login'),
          started_at: parse_time(deployment['created_at']),
          completed_at: terminal_status?(status_payload['state']) ? parse_time(status_payload['created_at']) : nil,
          last_event_at: parse_time(status_payload['updated_at'] || status_payload['created_at'] || deployment['created_at'])
        }
      end

      def normalize_status(status, conclusion)
        case status.to_s
        when 'queued', 'requested', 'waiting'
          'queued'
        when 'in_progress'
          'in_progress'
        when 'completed'
          case conclusion.to_s
          when 'success'
            'success'
          when 'failure'
            'failed'
          when 'cancelled', 'canceled'
            'canceled'
          when 'skipped'
            'skipped'
          else
            'unknown'
          end
        when 'success'
          'success'
        when 'failure', 'failed', 'error'
          'failed'
        when 'cancelled', 'canceled'
          'canceled'
        else
          'unknown'
        end
      end

      def terminal_status?(status)
        %w[success failed canceled].include?(normalize_status(status, nil))
      end

      def normalize_repository_data(payload)
        payload = normalize_hash(payload)
        {
          provider_repository_id: payload['id'].to_s,
          owner: payload.dig('owner', 'login') || '',
          repo_name: payload['name'] || '',
          full_name: payload['full_name'] || '',
          url: payload['html_url'] || '',
          description: payload['description']
        }
      end
    end
  end
end
