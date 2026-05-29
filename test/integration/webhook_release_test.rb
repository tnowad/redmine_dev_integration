# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/dev_integration_test_factory'

class WebhookReleaseTest < Redmine::IntegrationTest
  include DevIntegrationTestFactory
  include ActiveJob::TestHelper

  def setup
    RedmineDevIntegration::GithubWebhookSignatureVerifier.any_instance.stubs(:valid?).returns(true)
    Setting.stubs(:plugin_redmine_dev_integration).returns({
      'github_webhook_secret' => 'test_secret',
      'github_provider_enabled' => '1'
    })
    @project = Project.generate!
    @project.update_column(:issue_key_prefix, 'DEV')
    @issue = Issue.generate!(project: @project, subject: 'Test Release', author: User.find(1))
    @issue.reload
    @repo = create_external_repository(project: @project, provider: 'github', full_name: 'owner/repo', provider_repository_id: '12345')
  end

  def release_headers(delivery_id: 'release-test-001')
    {
      'X-Github-Event' => 'release',
      'X-Github-Delivery' => delivery_id,
      'Content-Type' => 'application/json'
    }
  end

  def test_github_release_webhook_creates_release
    payload = {
      action: 'published',
      release: {
        tag_name: 'v1.0.0',
        name: 'v1.0.0',
        body: 'Release v1.0.0 with DEV-1 fixes',
        html_url: 'https://github.com/owner/repo/releases/tag/v1.0.0',
        draft: false,
        author: { login: 'dev1' },
        published_at: '2026-01-01T10:00:00Z',
        created_at: '2026-01-01T09:00:00Z'
      },
      repository: {
        id: 12345,
        full_name: 'owner/repo',
        html_url: 'https://github.com/owner/repo'
      }
    }.to_json

    perform_enqueued_jobs do
      post '/dev_integrations/github/webhook',
           headers: release_headers(delivery_id: 'release-create-001'),
           params: payload
    end

    assert_response :accepted
    release = ExternalRelease.find_by(
      provider: 'github',
      external_repository: @repo,
      name: 'v1.0.0'
    )
    assert release, 'Expected ExternalRelease to be created'
    assert_equal 'v1.0.0', release.tag_name
    assert_equal 'published', release.status
    assert_equal 'Release v1.0.0 with DEV-1 fixes', release.body
    assert_equal 'dev1', release.author_login
  end

  def test_github_release_webhook_updates_existing_release
    ExternalRelease.create!(
      provider: 'github',
      external_repository: @repo,
      name: 'v1.0.0',
      tag_name: 'v1.0.0',
      status: 'draft',
      body: 'Old body'
    )

    payload = {
      action: 'published',
      release: {
        tag_name: 'v1.0.0',
        name: 'v1.0.0',
        body: 'Updated release notes',
        html_url: 'https://github.com/owner/repo/releases/tag/v1.0.0',
        draft: false,
        author: { login: 'dev1' },
        published_at: '2026-01-01T10:00:00Z',
        created_at: '2026-01-01T09:00:00Z'
      },
      repository: {
        id: 12345,
        full_name: 'owner/repo',
        html_url: 'https://github.com/owner/repo'
      }
    }.to_json

    perform_enqueued_jobs do
      post '/dev_integrations/github/webhook',
           headers: release_headers(delivery_id: 'release-update-001'),
           params: payload
    end

    assert_response :accepted
    release = ExternalRelease.find_by(
      provider: 'github',
      external_repository: @repo,
      name: 'v1.0.0'
    )
    assert_equal 'published', release.status
    assert_equal 'Updated release notes', release.body
  end

  def test_draft_release_is_marked_draft
    payload = {
      action: 'published',
      release: {
        tag_name: 'v2.0.0-beta',
        name: 'v2.0.0-beta',
        body: 'Pre-release',
        html_url: 'https://github.com/owner/repo/releases/tag/v2.0.0-beta',
        draft: true,
        author: { login: 'dev1' },
        published_at: '2026-01-01T10:00:00Z',
        created_at: '2026-01-01T09:00:00Z'
      },
      repository: {
        id: 12345,
        full_name: 'owner/repo',
        html_url: 'https://github.com/owner/repo'
      }
    }.to_json

    perform_enqueued_jobs do
      post '/dev_integrations/github/webhook',
           headers: release_headers(delivery_id: 'release-draft-001'),
           params: payload
    end

    assert_response :accepted
    release = ExternalRelease.find_by(
      provider: 'github',
      external_repository: @repo,
      name: 'v2.0.0-beta'
    )
    assert release, 'Expected draft ExternalRelease to be created'
    assert_equal 'draft', release.status
  end

  def test_release_linked_to_deployment_issues
    release = ExternalRelease.create!(
      provider: 'github',
      external_repository: @repo,
      name: 'v1.0.0',
      tag_name: 'v1.0.0',
      status: 'published'
    )
    deployment = ExternalDeployment.create!(
      provider: 'github',
      external_repository: @repo,
      external_release: release,
      provider_deployment_id: 'deploy-rel-1',
      environment_name: 'production',
      status: 'success',
      sha: 'abc123',
      ref: 'refs/tags/v1.0.0',
      branch_name: 'refs/tags/v1.0.0'
    )
    if @issue.issue_key.present?
      ExternalDeploymentIssue.create!(external_deployment: deployment, issue: @issue)
    end

    payload = {
      action: 'published',
      release: {
        tag_name: 'v1.0.0',
        name: 'v1.0.0',
        body: 'Release',
        html_url: 'https://github.com/owner/repo/releases/tag/v1.0.0',
        draft: false,
        author: { login: 'dev1' },
        published_at: '2026-01-01T10:00:00Z',
        created_at: '2026-01-01T09:00:00Z'
      },
      repository: {
        id: 12345,
        full_name: 'owner/repo',
        html_url: 'https://github.com/owner/repo'
      }
    }.to_json

    perform_enqueued_jobs do
      post '/dev_integrations/github/webhook',
           headers: release_headers(delivery_id: 'release-link-001'),
           params: payload
    end

    assert_response :accepted

    if @issue.issue_key.present?
      release.reload
      assert_equal [@issue.id], release.issues.pluck(:id)
    end
  end
end
