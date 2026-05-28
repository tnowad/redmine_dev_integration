# frozen_string_literal: true

require_relative '../test_helper'

class GitHubReleaseProcessorTest < ActiveSupport::TestCase
  fixtures :projects, :repositories

  def setup
    @processor = RedmineDevIntegration::GitHubReleaseProcessor.new
    @external_repository = ExternalRepository.create!(
      provider: 'github',
      provider_repository_id: '123',
      owner: 'redmine',
      repo_name: 'redmine_dev_integration',
      full_name: 'redmine/redmine_dev_integration',
      url: 'https://github.com/redmine/redmine_dev_integration',
      redmine_project: projects(:projects_001)
    )
  end

  def build_event(payload = {})
    ExternalProviderEvent.new({
      provider: 'github',
      delivery_id: "delivery-#{SecureRandom.hex(4)}",
      event_type: 'release',
      payload: JSON.generate(payload),
      status: 'pending'
    })
  end

  def test_creates_release_on_published_event
    event = build_event(
      action: 'published',
      release: {
        tag_name: 'v1.0.0',
        name: 'v1.0.0',
        body: 'First release',
        html_url: 'https://github.com/redmine/redmine_dev_integration/releases/tag/v1.0.0',
        draft: false,
        author: { login: 'contributor' },
        published_at: '2026-05-25T12:00:00Z',
        created_at: '2026-05-25T11:00:00Z'
      },
      repository: {
        id: 123,
        full_name: 'redmine/redmine_dev_integration'
      }
    )

    assert @processor.call(event)

    release = ExternalRelease.find_by(
      provider: 'github',
      external_repository: @external_repository,
      name: 'v1.0.0'
    )
    assert release, 'Expected ExternalRelease to be created'
    assert_equal 'v1.0.0', release.tag_name
    assert_equal 'First release', release.body
    assert_equal 'https://github.com/redmine/redmine_dev_integration/releases/tag/v1.0.0', release.url
    assert_equal 'published', release.status
    assert_equal 'contributor', release.author_login
    assert_equal Time.zone.parse('2026-05-25T12:00:00Z'), release.released_at
  end

  def test_creates_draft_release
    event = build_event(
      action: 'published',
      release: {
        tag_name: 'v2.0.0-beta',
        name: 'v2.0.0-beta',
        body: 'Beta release',
        html_url: 'https://github.com/redmine/redmine_dev_integration/releases/tag/v2.0.0-beta',
        draft: true,
        author: { login: 'developer' },
        published_at: '2026-05-25T12:00:00Z',
        created_at: '2026-05-25T11:00:00Z'
      },
      repository: {
        id: 123,
        full_name: 'redmine/redmine_dev_integration'
      }
    )

    assert @processor.call(event)

    release = ExternalRelease.find_by(
      provider: 'github',
      external_repository: @external_repository,
      name: 'v2.0.0-beta'
    )
    assert release
    assert_equal 'draft', release.status
  end

  def test_updates_existing_release
    ExternalRelease.create!(
      provider: 'github',
      external_repository: @external_repository,
      name: 'v1.0.0',
      tag_name: 'v1.0.0',
      status: 'draft',
      body: 'Old body'
    )

    event = build_event(
      action: 'published',
      release: {
        tag_name: 'v1.0.0',
        name: 'v1.0.0',
        body: 'Updated body',
        html_url: 'https://github.com/redmine/redmine_dev_integration/releases/tag/v1.0.0',
        draft: false,
        author: { login: 'contributor' },
        published_at: '2026-05-25T12:00:00Z',
        created_at: '2026-05-25T11:00:00Z'
      },
      repository: {
        id: 123,
        full_name: 'redmine/redmine_dev_integration'
      }
    )

    assert @processor.call(event)

    release = ExternalRelease.find_by(
      provider: 'github',
      external_repository: @external_repository,
      name: 'v1.0.0'
    )
    assert_equal 'Updated body', release.body
    assert_equal 'published', release.status
  end

  def test_ignores_non_release_events
    event = build_event(
      action: 'created',
      ref: 'refs/heads/main'
    )
    event.event_type = 'push'

    refute @processor.call(event)
    assert_equal 0, ExternalRelease.count
  end

  def test_ignores_non_github_provider
    event = build_event(
      action: 'published',
      release: { tag_name: 'v1.0.0' },
      repository: { id: 123 }
    )
    event.provider = 'gitlab'

    refute @processor.call(event)
    assert_equal 0, ExternalRelease.count
  end

  def test_ignores_event_with_empty_tag_name
    event = build_event(
      action: 'published',
      release: {
        tag_name: '',
        name: ''
      },
      repository: {
        id: 123,
        full_name: 'redmine/redmine_dev_integration'
      }
    )

    refute @processor.call(event)
    assert_equal 0, ExternalRelease.count
  end

  def test_ignores_edited_action
    event = build_event(
      action: 'edited',
      release: {
        tag_name: 'v1.0.0',
        name: 'v1.0.0'
      },
      repository: {
        id: 123,
        full_name: 'redmine/redmine_dev_integration'
      }
    )

    refute @processor.call(event)
    assert_equal 0, ExternalRelease.count
  end

  def test_ignores_missing_repository
    event = build_event(
      action: 'published',
      release: {
        tag_name: 'v1.0.0',
        name: 'v1.0.0'
      },
      repository: {
        id: 999,
        full_name: 'other/repo'
      }
    )

    refute @processor.call(event)
    assert_equal 0, ExternalRelease.count
  end

  def test_links_deployment_issues_to_release
    project = Project.generate!(issue_key_prefix: 'REL')
    @external_repository.update!(redmine_project: project)
    issue = Issue.generate!(project: project, subject: 'Release issue')
    release = ExternalRelease.create!(
      provider: 'github',
      external_repository: @external_repository,
      name: 'v1.0.0',
      tag_name: 'v1.0.0',
      status: 'published'
    )
    deployment = ExternalDeployment.create!(
      provider: 'github',
      external_repository: @external_repository,
      external_release: release,
      provider_deployment_id: 'deploy-1',
      environment_name: 'production',
      status: 'success',
      sha: 'abc123',
      ref: 'refs/tags/v1.0.0',
      branch_name: 'refs/tags/v1.0.0'
    )
    ExternalDeploymentIssue.create!(external_deployment: deployment, issue: issue)

    event = build_event(
      action: 'published',
      release: {
        tag_name: 'v1.0.0',
        name: 'v1.0.0',
        body: 'Updated',
        html_url: 'https://github.com/release',
        draft: false,
        author: { login: 'contributor' },
        published_at: '2026-05-25T12:00:00Z'
      },
      repository: {
        id: 123,
        full_name: 'redmine/redmine_dev_integration'
      }
    )

    assert @processor.call(event)
    assert_equal [issue.id], release.reload.issues.pluck(:id)
  end
end
