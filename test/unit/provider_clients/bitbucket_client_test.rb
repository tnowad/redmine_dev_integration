# frozen_string_literal: true

require_relative '../../test_helper'

class BitbucketClientTest < ActiveSupport::TestCase
  def test_credentials_are_required
    client = RedmineDevIntegration::ProviderClients::BitbucketClient.new(settings: {})

    assert_predicate client, :credentials_missing?
  end

  def test_credentials_missing_when_token_is_blank
    client = RedmineDevIntegration::ProviderClients::BitbucketClient.new(settings: {'bitbucket_api_token' => ''})

    assert_predicate client, :credentials_missing?
  end

  def test_credentials_present_when_token_is_set
    client = RedmineDevIntegration::ProviderClients::BitbucketClient.new(settings: {'bitbucket_api_token' => 'test-token'})

    assert_not_predicate client, :credentials_missing?
  end

  def test_recent_pull_requests_normalize_api_payload
    requests = []
    client = RedmineDevIntegration::ProviderClients::BitbucketClient.new(
      settings: {'bitbucket_api_token' => 'token'},
      http_getter: lambda do |uri, headers|
        requests << [uri.request_uri, headers]
        JSON.generate({
          'values' => [
            {
              'id' => 7,
              'title' => 'Add AUTH-1 support',
              'description' => 'Pull request body',
              'state' => 'OPEN',
              'author' => {'username' => 'contributor', 'display_name' => 'Contributor'},
              'source' => {'branch' => {'name' => 'feature/AUTH-1'}},
              'destination' => {'branch' => {'name' => 'main'}},
              'created_on' => '2026-05-25T10:00:00+00:00',
              'updated_on' => '2026-05-25T10:05:00+00:00',
              'links' => {'html' => {'href' => 'https://bitbucket.org/workspace/repo/pull-requests/7'}}
            }
          ]
        })
      end
    )
    repository = Struct.new(:full_name).new('workspace/repo')

    pull_requests = client.recent_pull_requests(repository: repository)

    assert_equal ['/2.0/repositories/workspace/repo/pullrequests?state=ALL&pagelen=10'], requests.map(&:first)
    assert_equal 'Bearer token', requests.first.last['Authorization']
    assert_equal 1, pull_requests.length
    assert_equal 7, pull_requests.first[:number]
    assert_equal 'feature/AUTH-1', pull_requests.first[:source_branch]
    assert_equal 'main', pull_requests.first[:target_branch]
    assert_equal 'open', pull_requests.first[:state]
    assert_equal 'contributor', pull_requests.first[:author_login]
  end

  def test_recent_builds_normalize_pipeline_data
    requests = []
    client = RedmineDevIntegration::ProviderClients::BitbucketClient.new(
      settings: {'bitbucket_api_token' => 'token'},
      http_getter: lambda do |uri, headers|
        requests << [uri.request_uri, headers]
        JSON.generate({
          'values' => [
            {
              'uuid' => '{abc123-def456-7890}',
              'build_number' => 42,
              'state' => {
                'name' => 'COMPLETED',
                'result' => {
                  'name' => 'SUCCESSFUL'
                }
              },
              'target' => {
                'commit' => {'hash' => 'abc123'},
                'ref_name' => 'feature/AUTH-1'
              },
              'creator' => {'username' => 'contributor'},
              'created_on' => '2026-05-25T10:00:00+00:00',
              'completed_on' => '2026-05-25T10:20:00+00:00',
              'updated_on' => '2026-05-25T10:20:00+00:00',
              'links' => {'html' => {'href' => 'https://bitbucket.org/workspace/repo/pipelines/results/42'}}
            }
          ]
        })
      end
    )
    repository = Struct.new(:full_name).new('workspace/repo')

    builds = client.recent_builds(repository: repository)

    assert_equal ['/2.0/repositories/workspace/repo/pipelines/?pagelen=10'], requests.map(&:first)
    assert_equal 1, builds.length
    assert_equal '{abc123-def456-7890}', builds.first[:provider_build_id]
    assert_equal 42, builds.first[:build_number]
    assert_equal 'success', builds.first[:status]
    assert_equal 'SUCCESSFUL', builds.first[:conclusion]
    assert_equal 'feature/AUTH-1', builds.first[:branch_name]
  end

  def test_recent_deployments_returns_empty_on_404
    client = RedmineDevIntegration::ProviderClients::BitbucketClient.new(
      settings: {'bitbucket_api_token' => 'token'},
      http_getter: lambda do |_uri, _headers|
        response = Net::HTTPNotFound.new('1.1', '404', 'Not Found')
        raise Net::HTTPNotFound.new('Not Found', response, nil)
      end
    )
    repository = Struct.new(:full_name).new('workspace/repo')

    deployments = client.recent_deployments(repository: repository)

    assert_equal [], deployments
  end

  def test_recent_builds_returns_empty_on_404
    client = RedmineDevIntegration::ProviderClients::BitbucketClient.new(
      settings: {'bitbucket_api_token' => 'token'},
      http_getter: lambda do |_uri, _headers|
        response = Net::HTTPNotFound.new('1.1', '404', 'Not Found')
        raise Net::HTTPNotFound.new('Not Found', response, nil)
      end
    )
    repository = Struct.new(:full_name).new('workspace/repo')

    builds = client.recent_builds(repository: repository)

    assert_equal [], builds
  end

  def test_repository_lookup_returns_normalized_data
    client = RedmineDevIntegration::ProviderClients::BitbucketClient.new(
      settings: {'bitbucket_api_token' => 'token'},
      http_getter: lambda do |_uri, _headers|
        JSON.generate({
          'uuid' => '{abc123-def456-7890-0123-456789abcdef}',
          'slug' => 'repo',
          'full_name' => 'workspace/repo',
          'description' => 'A test repository',
          'owner' => {'username' => 'workspace'},
          'workspace' => {'slug' => 'workspace'},
          'links' => {'html' => {'href' => 'https://bitbucket.org/workspace/repo'}}
        })
      end
    )

    data = client.repository_lookup('workspace/repo')

    assert_equal '{abc123-def456-7890-0123-456789abcdef}', data[:provider_repository_id]
    assert_equal 'workspace', data[:owner]
    assert_equal 'repo', data[:repo_name]
    assert_equal 'workspace/repo', data[:full_name]
    assert_equal 'https://bitbucket.org/workspace/repo', data[:url]
    assert_equal 'A test repository', data[:description]
  end

  def test_repository_lookup_raises_on_404
    response = Net::HTTPNotFound.new('1.1', '404', 'Not Found')
    client = RedmineDevIntegration::ProviderClients::BitbucketClient.new(
      settings: {'bitbucket_api_token' => 'token'},
      http_getter: lambda do |_uri, _headers|
        raise Net::HTTPClientException.new('404 Not Found', response)
      end
    )

    assert_raises(RedmineDevIntegration::ProviderClients::RepositoryNotFoundError) do
      client.repository_lookup('nonexistent/repo')
    end
  end

  def test_list_webhooks_returns_empty_on_error
    client = RedmineDevIntegration::ProviderClients::BitbucketClient.new(
      settings: {'bitbucket_api_token' => 'token'},
      http_getter: lambda do |_uri, _headers|
        raise StandardError, 'network error'
      end
    )
    repository = Struct.new(:full_name).new('workspace/repo')

    hooks = client.list_webhooks(repository: repository)

    assert_equal [], hooks
  end

  def test_create_webhook_posts_to_correct_endpoint
    requests = []
    client = RedmineDevIntegration::ProviderClients::BitbucketClient.new(
      settings: {'bitbucket_api_token' => 'token'},
      http_getter: lambda do |uri, headers|
        requests << [uri.request_uri, headers, 'GET']
        '{}'
      end
    )
    client.define_singleton_method(:post_request) do |uri, body:, headers:|
      requests << [uri.request_uri, headers, 'POST', body]
      Struct.new(:body).new(JSON.generate({'uuid' => 'hook-uuid'}))
    end
    repository = Struct.new(:full_name).new('workspace/repo')

    client.create_webhook(repository: repository, url: 'https://redmine.example.com/webhooks/bitbucket', secret: 'secret')

    post_call = requests.find { |r| r[2] == 'POST' }
    assert_not_nil post_call
    assert_equal '/2.0/repositories/workspace/repo/hooks', post_call[0]
    assert_equal 'https://redmine.example.com/webhooks/bitbucket', post_call[3][:url]
    assert_equal true, post_call[3][:active]
    assert_includes post_call[3][:events], 'repo:push'
    assert_includes post_call[3][:events], 'pullrequest:created'
  end

  def test_handles_merged_pull_request_state
    requests = []
    client = RedmineDevIntegration::ProviderClients::BitbucketClient.new(
      settings: {'bitbucket_api_token' => 'token'},
      http_getter: lambda do |uri, headers|
        requests << [uri.request_uri, headers]
        JSON.generate({
          'values' => [
            {
              'id' => 10,
              'title' => 'Merged PR',
              'state' => 'MERGED',
              'author' => {'username' => 'dev'},
              'source' => {'branch' => {'name' => 'feature/auth'}},
              'destination' => {'branch' => {'name' => 'main'}},
              'created_on' => '2026-05-25T10:00:00+00:00',
              'updated_on' => '2026-05-25T12:00:00+00:00',
              'links' => {'html' => {'href' => 'https://bitbucket.org/workspace/repo/pull-requests/10'}}
            }
          ]
        })
      end
    )
    repository = Struct.new(:full_name).new('workspace/repo')

    pull_requests = client.recent_pull_requests(repository: repository)

    assert_equal 'closed', pull_requests.first[:state]
    assert pull_requests.first[:merged]
  end
end
