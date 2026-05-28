# frozen_string_literal: true

require_relative '../test_helper'

class GitlabReleaseProcessorTest < ActiveSupport::TestCase
  fixtures :projects, :repositories

  def setup
    @processor = RedmineDevIntegration::GitlabReleaseProcessor.new
    @external_repository = ExternalRepository.create!(
      provider: 'gitlab',
      provider_repository_id: '456',
      owner: 'redmine',
      repo_name: 'redmine_dev_integration',
      full_name: 'redmine/redmine_dev_integration',
      url: 'https://gitlab.com/redmine/redmine_dev_integration',
      redmine_project: projects(:projects_001)
    )
  end

  def build_event(payload = {})
    ExternalProviderEvent.new({
      provider: 'gitlab',
      delivery_id: "delivery-#{SecureRandom.hex(4)}",
      event_type: 'Release Hook',
      payload: JSON.generate(payload),
      status: 'pending'
    })
  end

  def test_creates_release_from_release_hook
    event = build_event(
      object_kind: 'release',
      project: { id: 456, web_url: 'https://gitlab.com/redmine/redmine_dev_integration' },
      tag: 'v1.0.0',
      name: 'v1.0.0',
      description: 'First release',
      url: 'https://gitlab.com/redmine/redmine_dev_integration/-/releases/v1.0.0',
      commit: {
        author: { name: 'Developer' }
      },
      released_at: '2026-05-25T12:00:00Z',
      created_at: '2026-05-25T11:00:00Z'
    )

    assert @processor.call(event)

    release = ExternalRelease.find_by(
      provider: 'gitlab',
      external_repository: @external_repository,
      name: 'v1.0.0'
    )
    assert release, 'Expected ExternalRelease to be created'
    assert_equal 'v1.0.0', release.tag_name
    assert_equal 'First release', release.body
    assert_equal 'https://gitlab.com/redmine/redmine_dev_integration/-/releases/v1.0.0', release.url
    assert_equal 'published', release.status
    assert_equal 'Developer', release.author_login
    assert_equal Time.zone.parse('2026-05-25T12:00:00Z'), release.released_at
  end

  def test_updates_existing_release
    ExternalRelease.create!(
      provider: 'gitlab',
      external_repository: @external_repository,
      name: 'v1.0.0',
      tag_name: 'v1.0.0',
      status: 'published',
      body: 'Old description'
    )

    event = build_event(
      object_kind: 'release',
      project: { id: 456, web_url: 'https://gitlab.com/redmine/redmine_dev_integration' },
      tag: 'v1.0.0',
      name: 'v1.0.0',
      description: 'Updated description',
      url: 'https://gitlab.com/redmine/redmine_dev_integration/-/releases/v1.0.0',
      commit: {
        author: { name: 'Developer' }
      },
      released_at: '2026-05-25T12:00:00Z',
      created_at: '2026-05-25T11:00:00Z'
    )

    assert @processor.call(event)

    release = ExternalRelease.find_by(
      provider: 'gitlab',
      external_repository: @external_repository,
      name: 'v1.0.0'
    )
    assert_equal 'Updated description', release.body
  end

  def test_ignores_non_release_hook_events
    event = build_event(
      object_kind: 'push',
      project: { id: 456 },
      ref: 'refs/heads/main'
    )
    event.event_type = 'Push Hook'

    refute @processor.call(event)
    assert_equal 0, ExternalRelease.count
  end

  def test_ignores_non_gitlab_provider
    event = build_event(
      object_kind: 'release',
      project: { id: 456 },
      tag: 'v1.0.0'
    )
    event.provider = 'github'

    refute @processor.call(event)
    assert_equal 0, ExternalRelease.count
  end

  def test_ignores_event_with_empty_tag
    event = build_event(
      object_kind: 'release',
      project: { id: 456, web_url: 'https://gitlab.com/redmine/redmine_dev_integration' },
      tag: '',
      name: ''
    )

    refute @processor.call(event)
    assert_equal 0, ExternalRelease.count
  end

  def test_ignores_missing_repository
    event = build_event(
      object_kind: 'release',
      project: { id: 999, web_url: 'https://gitlab.com/other/repo' },
      tag: 'v1.0.0',
      name: 'v1.0.0'
    )

    refute @processor.call(event)
    assert_equal 0, ExternalRelease.count
  end

  def test_links_deployment_issues_to_release
    project = Project.generate!(issue_key_prefix: 'REL')
    @external_repository.update!(redmine_project: project)
    issue = Issue.generate!(project: project, subject: 'Release issue')
    release = ExternalRelease.create!(
      provider: 'gitlab',
      external_repository: @external_repository,
      name: 'v1.0.0',
      tag_name: 'v1.0.0',
      status: 'published'
    )
    deployment = ExternalDeployment.create!(
      provider: 'gitlab',
      external_repository: @external_repository,
      external_release: release,
      provider_deployment_id: 'deploy-gl-1',
      environment_name: 'production',
      status: 'success',
      sha: 'abc123',
      ref: 'refs/tags/v1.0.0',
      branch_name: 'refs/tags/v1.0.0'
    )
    ExternalDeploymentIssue.create!(external_deployment: deployment, issue: issue)

    event = build_event(
      object_kind: 'release',
      project: { id: 456, web_url: 'https://gitlab.com/redmine/redmine_dev_integration' },
      tag: 'v1.0.0',
      name: 'v1.0.0',
      description: 'Updated',
      url: 'https://gitlab.com/release',
      commit: {
        author: { name: 'Developer' }
      },
      released_at: '2026-05-25T12:00:00Z'
    )

    assert @processor.call(event)
    assert_equal [issue.id], release.reload.issues.pluck(:id)
  end
end
