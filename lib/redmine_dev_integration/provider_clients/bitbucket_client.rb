# frozen_string_literal: true

module RedmineDevIntegration
  module ProviderClients
    class BitbucketClient < BaseClient
      def credentials_missing?
        api_token.blank?
      end

      def recent_pull_requests(repository:)
        compact_collection(fetch_json(api_uri("/repositories/#{repository.full_name}/pullrequests?state=ALL&pagelen=10"), headers: auth_headers), 'values').map do |pr|
          normalize_pull_request(pr)
        end
      rescue StandardError
        []
      end

      def recent_builds(repository:)
        payload = fetch_json(api_uri("/repositories/#{repository.full_name}/pipelines/?pagelen=10"), headers: auth_headers)
        compact_collection(payload, 'values').map do |pipeline|
          normalize_build(pipeline)
        end
      rescue Net::HTTPNotFound
        []
      rescue StandardError
        []
      end

      def recent_deployments(repository:)
        payload = fetch_json(api_uri("/repositories/#{repository.full_name}/deployments/"), headers: auth_headers)
        compact_collection(payload, 'values').map do |deployment|
          normalize_deployment(deployment)
        end
      rescue Net::HTTPNotFound
        []
      rescue StandardError
        []
      end

      def repository_lookup(repository_path)
        payload = fetch_json(api_uri("/repositories/#{repository_path}"), headers: auth_headers)
        normalize_repository_data(payload)
      rescue Net::HTTPClientException => e
        if e.message.include?('404') || e.message.include?('Not Found')
          raise RepositoryNotFoundError, "Repository '#{repository_path}' not found on Bitbucket"
        end
        raise AuthenticationError, "Bitbucket API authentication failed"
      end

      def list_repositories
        repos = paginated_get(api_uri('/repositories?role=member&pagelen=100'), headers: auth_headers, max_pages: 3, collection_key: 'values')
        repos.map { |r| normalize_repository_data(r) }
      rescue StandardError
        []
      end

      def list_webhooks(repository:)
        compact_collection(fetch_json(api_uri("/repositories/#{repository.full_name}/hooks"), headers: auth_headers), 'values')
      rescue StandardError
        []
      end

      def create_webhook(repository:, url:, secret:)
        body = {
          description: 'Redmine Dev Integration webhook',
          url: url,
          active: true,
          events: %w[repo:push pullrequest:created pullrequest:updated pullrequest:fulfilled pullrequest:rejected]
        }
        post_json(api_uri("/repositories/#{repository.full_name}/hooks"), body: body, headers: auth_headers.merge('Content-Type' => 'application/json'))
      end

      def update_webhook(repository:, webhook_id:, url:, secret:)
        body = {
          description: 'Redmine Dev Integration webhook',
          url: url,
          active: true,
          events: %w[repo:push pullrequest:created pullrequest:updated pullrequest:fulfilled pullrequest:rejected]
        }
        put_json(api_uri("/repositories/#{repository.full_name}/hooks/#{webhook_id}"), body: body, headers: auth_headers.merge('Content-Type' => 'application/json'))
      end

      private

      def api_token
        oauth_token = oauth_access_token
        return oauth_token if oauth_token.present?

        setting_value('bitbucket_api_token')
      end

      def oauth_access_token
        return nil unless defined?(RedmineDevIntegration::Oauth::TokenStore)
        RedmineDevIntegration::Oauth::TokenStore.access_token('bitbucket')
      end

      def auth_headers
        {
          'Authorization' => "Bearer #{api_token}",
          'Accept' => 'application/json'
        }
      end

      def api_uri(path)
        URI.join('https://api.bitbucket.org/2.0/', path.sub(%r{\A/}, ''))
      end

      def normalize_pull_request(pr)
        pr = normalize_hash(pr)
        {
          number: pr['id'],
          title: pr['title'],
          body: pr['description'] || pr['summary'] || pr['body'],
          url: pr.dig('links', 'html', 'href'),
          state: normalize_pr_state(pr['state']),
          author_login: pr.dig('author', 'username') || pr.dig('author', 'display_name'),
          source_branch: pr.dig('source', 'branch', 'name'),
          target_branch: pr.dig('destination', 'branch', 'name'),
          merged: pr['state'] == 'MERGED',
          merged_at: parse_time(pr['updated_on']),
          opened_at: parse_time(pr['created_on']),
          closed_at: %w[MERGED DECLINED].include?(pr['state']) ? parse_time(pr['updated_on']) : nil,
          last_event_at: parse_time(pr['updated_on'] || pr['created_on'])
        }
      end

      def normalize_build(pipeline)
        pipeline = normalize_hash(pipeline)
        state = pipeline.dig('state', 'name') || pipeline['state']
        result = pipeline.dig('state', 'result', 'name') || pipeline.dig('state', 'result')

        {
          provider_build_id: pipeline['uuid'],
          build_number: pipeline['build_number'],
          name: "Pipeline ##{pipeline['build_number']}",
          status: normalize_pipeline_status(state, result),
          conclusion: result,
          url: pipeline.dig('links', 'html', 'href') || pipeline.dig('repository', 'links', 'html', 'href'),
          sha: pipeline.dig('target', 'commit', 'hash') || pipeline.dig('target', 'hash'),
          ref: pipeline.dig('target', 'ref_name') || pipeline['ref_name'],
          branch_name: pipeline.dig('target', 'ref_name') || pipeline['ref_name'],
          author_login: pipeline.dig('creator', 'username') || pipeline.dig('creator', 'display_name'),
          started_at: parse_time(pipeline['created_on']),
          finished_at: parse_time(pipeline['completed_on']),
          last_event_at: parse_time(pipeline['updated_on'] || pipeline['completed_on'] || pipeline['created_on'])
        }
      end

      def normalize_deployment(deployment)
        deployment = normalize_hash(deployment)
        release = deployment['release'].is_a?(Hash) ? deployment['release'] : {}
        environment = deployment['environment'].is_a?(Hash) ? deployment['environment'] : {}

        {
          provider_deployment_id: deployment['uuid'],
          environment_name: environment['name'] || deployment['environment_name'] || 'unknown',
          environment_url: release['url'],
          status: normalize_deployment_status(deployment['state']),
          sha: release['commit'] || release['sha'],
          ref: release['name'] || deployment.dig('target', 'ref_name'),
          branch_name: release['name'] || deployment.dig('target', 'ref_name'),
          description: deployment['comment'] || release['name'],
          creator_login: deployment.dig('deployer', 'username') || deployment.dig('deployer', 'display_name'),
          started_at: parse_time(deployment['started_on'] || deployment['created_on']),
          completed_at: parse_time(deployment['completed_on']),
          last_event_at: parse_time(deployment['completed_on'] || deployment['started_on'] || deployment['created_on'])
        }
      end

      def normalize_repository_data(payload)
        payload = normalize_hash(payload)
        owner_data = payload['owner'].is_a?(Hash) ? payload['owner'] : {}
        workspace_data = payload['workspace'].is_a?(Hash) ? payload['workspace'] : {}

        {
          provider_repository_id: payload['uuid'].to_s,
          owner: owner_data['username'] || workspace_data['slug'] || '',
          repo_name: payload['slug'] || payload['name'] || '',
          full_name: payload['full_name'] || '',
          url: payload.dig('links', 'html', 'href') || '',
          description: payload['description']
        }
      end

      def normalize_pr_state(state)
        case state.to_s
        when 'OPEN' then 'open'
        when 'MERGED', 'DECLINED', 'SUPERSEDED' then 'closed'
        else 'open'
        end
      end

      def normalize_pipeline_status(state, result)
        return normalize_result_status(result) if state.to_s == 'COMPLETED'

        case state.to_s
        when 'PENDING', 'IN_PROGRESS' then 'in_progress'
        else 'in_progress'
        end
      end

      def normalize_result_status(result)
        case result.to_s
        when 'SUCCESSFUL' then 'success'
        when 'FAILED' then 'failed'
        when 'STOPPED', 'HALTED' then 'canceled'
        else 'unknown'
        end
      end

      def normalize_deployment_status(state)
        case state.to_s
        when 'PENDING' then 'pending'
        when 'IN_PROGRESS' then 'in_progress'
        when 'COMPLETED' then 'success'
        when 'FAILED' then 'failed'
        when 'STOPPED', 'ABORTED' then 'canceled'
        else 'unknown'
        end
      end
    end
  end
end
