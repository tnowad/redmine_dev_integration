# frozen_string_literal: true

require_relative '../test_helper'

class GitHubDeploymentStatusProcessorTest < ActiveSupport::TestCase
  fixtures :projects, :repositories

  def setup
    @processor = RedmineDevIntegration::GitHubDeploymentStatusProcessor.new
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

  def build_event(attributes = {})
    ExternalProviderEvent.new({
      provider: 'github',
      delivery_id: "delivery-#{SecureRandom.hex(4)}",
      event_type: 'deployment_status',
      payload: JSON.generate({
        repository: {
          id: 123,
          html_url: 'https://github.com/redmine/redmine_dev_integration'
        },
        deployment: {
          id: 9001,
          environment: 'staging',
          sha: 'abc123',
          ref: 'main',
          description: 'Deploy AUTH-1 to staging',
          creator: {login: 'contributor'},
          created_at: '2026-05-25T10:00:00Z'
        },
        deployment_status: {
          state: 'pending',
          environment_url: 'https://staging.example.test',
          target_url: 'https://staging.example.test',
          description: 'Deploy AUTH-1 to staging',
          creator: {login: 'contributor'},
          created_at: '2026-05-25T11:00:00Z',
          updated_at: '2026-05-25T11:05:00Z'
        }
      }),
      status: 'pending'
    }.merge(attributes))
  end

  def test_deployment_status_creates_deployment_and_links_issues
    project = Project.generate!(issue_key_prefix: 'AUTH')
    issue = Issue.generate!(project: project, subject: 'Deployment target')
    @external_repository.update!(redmine_project: project)

    event = build_event(payload: JSON.generate({
      repository: {
        id: 123,
        html_url: 'https://github.com/redmine/redmine_dev_integration'
      },
      deployment: {
        id: 9001,
        environment: 'staging',
        sha: 'abc123',
        ref: "feature/#{issue.issue_key}-login",
        description: "Deploy #{issue.issue_key} to staging",
        creator: {login: 'contributor'},
        created_at: '2026-05-25T10:00:00Z'
      },
      deployment_status: {
        state: 'success',
        environment_url: 'https://staging.example.test',
        target_url: 'https://staging.example.test',
        description: "Deploy #{issue.issue_key} to staging",
        creator: {login: 'contributor'},
        created_at: '2026-05-25T11:00:00Z',
        updated_at: '2026-05-25T11:05:00Z'
      }
    }))

    assert @processor.call(event)

    deployment = ExternalDeployment.find_by!(
      provider: 'github',
      external_repository: @external_repository,
      provider_deployment_id: '9001',
      environment_name: 'staging'
    )

    assert_equal 'https://staging.example.test', deployment.environment_url
    assert_equal 'success', deployment.status
    assert_equal 'abc123', deployment.sha
    assert_equal "feature/#{issue.issue_key}-login", deployment.ref
    assert_equal "feature/#{issue.issue_key}-login", deployment.branch_name
    assert_equal "Deploy #{issue.issue_key} to staging", deployment.description
    assert_equal 'contributor', deployment.creator_login
    assert_equal Time.zone.parse('2026-05-25T10:00:00Z'), deployment.started_at
    assert_equal Time.zone.parse('2026-05-25T11:00:00Z'), deployment.completed_at
    assert_equal Time.zone.parse('2026-05-25T11:05:00Z'), deployment.last_event_at
    assert_equal [issue.id], deployment.issues.pluck(:id)
    assert_equal 1, deployment.external_deployment_issues.count
  end

  def test_deployment_status_updates_existing_deployment_without_duplication
    first_event = build_event(payload: JSON.generate({
      repository: {
        id: 123,
        html_url: 'https://github.com/redmine/redmine_dev_integration'
      },
      deployment: {
        id: 9001,
        environment: 'staging',
        sha: 'abc123',
        ref: 'main',
        description: 'Deploy to staging',
        creator: {login: 'contributor'},
        created_at: '2026-05-25T10:00:00Z'
      },
      deployment_status: {
        state: 'pending',
        environment_url: 'https://staging.example.test',
        target_url: 'https://staging.example.test',
        description: 'Deploy to staging',
        creator: {login: 'contributor'},
        created_at: '2026-05-25T11:00:00Z',
        updated_at: '2026-05-25T11:05:00Z'
      }
    }))

    second_event = build_event(payload: JSON.generate({
      repository: {
        id: 123,
        html_url: 'https://github.com/redmine/redmine_dev_integration'
      },
      deployment: {
        id: 9001,
        environment: 'staging',
        sha: 'def456',
        ref: 'main',
        description: 'Deploy to staging',
        creator: {login: 'contributor'},
        created_at: '2026-05-25T10:00:00Z'
      },
      deployment_status: {
        state: 'failed',
        environment_url: 'https://staging.example.test',
        target_url: 'https://staging.example.test',
        description: 'Deploy to staging',
        creator: {login: 'contributor'},
        created_at: '2026-05-25T12:00:00Z',
        updated_at: '2026-05-25T12:05:00Z'
      }
    }))

    assert @processor.call(first_event)
    assert @processor.call(second_event)

    assert_equal 1, ExternalDeployment.where(
      provider: 'github',
      external_repository: @external_repository,
      provider_deployment_id: '9001',
      environment_name: 'staging'
    ).count

    deployment = ExternalDeployment.find_by!(
      provider: 'github',
      external_repository: @external_repository,
      provider_deployment_id: '9001',
      environment_name: 'staging'
    )

    assert_equal 'failed', deployment.status
    assert_equal 'def456', deployment.sha
    assert_equal Time.zone.parse('2026-05-25T12:00:00Z'), deployment.completed_at
    assert_equal Time.zone.parse('2026-05-25T12:05:00Z'), deployment.last_event_at
  end

  def test_missing_repository_is_ignored_without_error
    event = build_event(payload: JSON.generate({
      repository: {
        id: 999,
        html_url: 'https://github.com/other/repo'
      },
      deployment: {
        id: 9001,
        environment: 'staging',
        sha: 'abc123',
        ref: 'main',
        description: 'Deploy AUTH-9999 to staging',
        creator: {login: 'contributor'},
        created_at: '2026-05-25T10:00:00Z'
      },
      deployment_status: {
        state: 'success',
        environment_url: 'https://staging.example.test',
        target_url: 'https://staging.example.test',
        description: 'Deploy AUTH-9999 to staging',
        creator: {login: 'contributor'},
        created_at: '2026-05-25T11:00:00Z',
        updated_at: '2026-05-25T11:05:00Z'
      }
    }))

    refute @processor.call(event)
    assert_nil ExternalDeployment.find_by(provider: 'github', provider_deployment_id: '9001')
  end

  def test_unknown_issue_key_does_not_fail_processing
    event = build_event(payload: JSON.generate({
      repository: {
        id: 123,
        html_url: 'https://github.com/redmine/redmine_dev_integration'
      },
      deployment: {
        id: 9002,
        environment: 'production',
        sha: 'abc123',
        ref: 'main',
        description: 'Deploy AUTH-9999 to production',
        creator: {login: 'contributor'},
        created_at: '2026-05-25T10:00:00Z'
      },
      deployment_status: {
        state: 'success',
        environment_url: 'https://prod.example.test',
        target_url: 'https://prod.example.test',
        description: 'Deploy AUTH-9999 to production',
        creator: {login: 'contributor'},
        created_at: '2026-05-25T11:00:00Z',
        updated_at: '2026-05-25T11:05:00Z'
      }
    }))

    assert_nothing_raised do
      assert @processor.call(event)
    end

    deployment = ExternalDeployment.find_by!(
      provider: 'github',
      external_repository: @external_repository,
      provider_deployment_id: '9002',
      environment_name: 'production'
    )
    assert_empty deployment.issues
  end

  def test_deployment_status_links_issue_via_sha_when_text_matching_finds_none
    project = Project.generate!(issue_key_prefix: 'AUTH')
    issue = Issue.generate!(project: project, subject: 'Trace target')
    @external_repository.update!(redmine_project: project)

    pull_request = ExternalPullRequest.create!(
      provider: 'github',
      external_repository: @external_repository,
      number: 11,
      title: 'Trace PR',
      url: 'https://github.com/redmine/redmine_dev_integration/pull/11',
      state: 'open',
      merged: false,
      source_sha: 'abc123'
    )
    ExternalPullRequestIssue.create!(external_pull_request: pull_request, issue: issue)

    event = build_event(payload: JSON.generate({
      repository: {
        id: 123,
        html_url: 'https://github.com/redmine/redmine_dev_integration'
      },
      deployment: {
        id: 9003,
        environment: 'production',
        sha: 'abc123',
        ref: 'main',
        description: 'Release',
        creator: {login: 'contributor'},
        created_at: '2026-05-25T10:00:00Z'
      },
      deployment_status: {
        state: 'success',
        environment_url: 'https://prod.example.test',
        target_url: 'https://prod.example.test',
        description: 'Release',
        creator: {login: 'contributor'},
        created_at: '2026-05-25T11:00:00Z',
        updated_at: '2026-05-25T11:05:00Z'
      }
    }))

    assert @processor.call(event)

    deployment = ExternalDeployment.find_by!(
      provider: 'github',
      external_repository: @external_repository,
      provider_deployment_id: '9003',
      environment_name: 'production'
    )
    assert_equal [issue.id], deployment.issues.pluck(:id)
    assert_equal 1, deployment.external_deployment_issues.count
  end
end
