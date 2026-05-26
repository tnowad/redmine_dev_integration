# frozen_string_literal: true

require_relative '../test_helper'

class GitlabDeploymentProcessorTest < ActiveSupport::TestCase
  fixtures :projects, :repositories

  def setup
    @processor = RedmineDevIntegration::GitlabDeploymentProcessor.new
    @external_repository = ExternalRepository.create!(
      provider: 'gitlab',
      provider_repository_id: '456',
      owner: 'redmine',
      repo_name: 'redmine_dev_integration',
      full_name: 'redmine/redmine_dev_integration',
      url: 'https://gitlab.example.com/redmine/redmine_dev_integration',
      redmine_project: projects(:projects_001)
    )
  end

  def build_event(attributes = {})
    ExternalProviderEvent.new({
      provider: 'gitlab',
      delivery_id: "delivery-#{SecureRandom.hex(4)}",
      event_type: 'Deployment Hook',
      payload: JSON.generate({
        deployment_id: 9001,
        environment: 'staging',
        environment_external_url: 'https://staging.example.test',
        status: 'created',
        sha: 'abc123',
        ref: 'main',
        commit_title: 'Deploy to staging',
        user: {
          username: 'contributor',
          name: 'Contributor'
        },
        deployable_started_at: '2026-05-25T10:00:00Z',
        deployable_finished_at: nil,
        created_at: '2026-05-25T10:00:00Z',
        updated_at: '2026-05-25T10:05:00Z',
        project: {
          id: 456,
          web_url: 'https://gitlab.example.com/redmine/redmine_dev_integration'
        }
      }),
      status: 'pending'
    }.merge(attributes))
  end

  def test_deployment_hook_creates_deployment_and_links_issues
    project = Project.generate!(issue_key_prefix: 'AUTH')
    issue = Issue.generate!(project: project, subject: 'Deployment target')
    @external_repository.update!(redmine_project: project)

    event = build_event(payload: JSON.generate({
      deployment_id: 9001,
      environment: 'staging',
      environment_external_url: 'https://staging.example.test',
      status: 'success',
      sha: 'abc123',
      ref: "feature/#{issue.issue_key}-login",
      commit_title: "Deploy #{issue.issue_key} to staging",
      user: {
        username: 'contributor',
        name: 'Contributor'
      },
      deployable_started_at: '2026-05-25T10:00:00Z',
      deployable_finished_at: '2026-05-25T10:20:00Z',
      created_at: '2026-05-25T10:00:00Z',
      updated_at: '2026-05-25T10:25:00Z',
      project: {
        id: 456,
        web_url: 'https://gitlab.example.com/redmine/redmine_dev_integration'
      }
    }))

    assert @processor.call(event)

    deployment = ExternalDeployment.find_by!(
      provider: 'gitlab',
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
    assert_equal Time.zone.parse('2026-05-25T10:20:00Z'), deployment.completed_at
    assert_equal Time.zone.parse('2026-05-25T10:25:00Z'), deployment.last_event_at
    assert_equal [issue.id], deployment.issues.pluck(:id)
    assert_equal 1, deployment.external_deployment_issues.count
  end

  def test_deployment_hook_updates_existing_deployment_without_duplication
    first_event = build_event(payload: JSON.generate({
      deployment_id: 9001,
      environment: 'staging',
      environment_external_url: 'https://staging.example.test',
      status: 'pending',
      sha: 'abc123',
      ref: 'main',
      commit_title: 'Deploy to staging',
      user: {
        username: 'contributor',
        name: 'Contributor'
      },
      deployable_started_at: '2026-05-25T10:00:00Z',
      created_at: '2026-05-25T10:00:00Z',
      updated_at: '2026-05-25T10:05:00Z',
      project: {
        id: 456,
        web_url: 'https://gitlab.example.com/redmine/redmine_dev_integration'
      }
    }))

    second_event = build_event(payload: JSON.generate({
      deployment_id: 9001,
      environment: 'staging',
      environment_external_url: 'https://staging.example.test',
      status: 'failed',
      sha: 'def456',
      ref: 'main',
      commit_title: 'Deploy to staging',
      user: {
        username: 'contributor',
        name: 'Contributor'
      },
      deployable_started_at: '2026-05-25T10:00:00Z',
      deployable_finished_at: '2026-05-25T11:00:00Z',
      created_at: '2026-05-25T10:00:00Z',
      updated_at: '2026-05-25T11:05:00Z',
      project: {
        id: 456,
        web_url: 'https://gitlab.example.com/redmine/redmine_dev_integration'
      }
    }))

    assert @processor.call(first_event)
    assert @processor.call(second_event)

    assert_equal 1, ExternalDeployment.where(
      provider: 'gitlab',
      external_repository: @external_repository,
      provider_deployment_id: '9001',
      environment_name: 'staging'
    ).count

    deployment = ExternalDeployment.find_by!(
      provider: 'gitlab',
      external_repository: @external_repository,
      provider_deployment_id: '9001',
      environment_name: 'staging'
    )

    assert_equal 'failed', deployment.status
    assert_equal 'def456', deployment.sha
    assert_equal Time.zone.parse('2026-05-25T11:00:00Z'), deployment.completed_at
    assert_equal Time.zone.parse('2026-05-25T11:05:00Z'), deployment.last_event_at
  end

  def test_missing_repository_is_ignored_without_error
    event = build_event(payload: JSON.generate({
      deployment_id: 9001,
      environment: 'staging',
      environment_external_url: 'https://staging.example.test',
      status: 'success',
      sha: 'abc123',
      ref: 'main',
      commit_title: 'Deploy AUTH-9999 to staging',
      user: {
        username: 'contributor',
        name: 'Contributor'
      },
      deployable_started_at: '2026-05-25T10:00:00Z',
      deployable_finished_at: '2026-05-25T10:20:00Z',
      created_at: '2026-05-25T10:00:00Z',
      updated_at: '2026-05-25T10:25:00Z',
      project: {
        id: 999,
        web_url: 'https://gitlab.example.com/other/repo'
      }
    }))

    refute @processor.call(event)
    assert_nil ExternalDeployment.find_by(provider: 'gitlab', provider_deployment_id: '9001')
  end

  def test_unknown_issue_key_does_not_fail_processing
    event = build_event(payload: JSON.generate({
      deployment_id: 9002,
      environment: 'production',
      environment_external_url: 'https://prod.example.test',
      status: 'success',
      sha: 'abc123',
      ref: 'feature/AUTH-9999-login',
      commit_title: 'Deploy AUTH-9999 to production',
      user: {
        username: 'contributor',
        name: 'Contributor'
      },
      deployable_started_at: '2026-05-25T10:00:00Z',
      deployable_finished_at: '2026-05-25T10:20:00Z',
      created_at: '2026-05-25T10:00:00Z',
      updated_at: '2026-05-25T10:25:00Z',
      project: {
        id: 456,
        web_url: 'https://gitlab.example.com/redmine/redmine_dev_integration'
      }
    }))

    assert_nothing_raised do
      assert @processor.call(event)
    end

    deployment = ExternalDeployment.find_by!(
      provider: 'gitlab',
      external_repository: @external_repository,
      provider_deployment_id: '9002',
      environment_name: 'production'
    )

    assert_empty deployment.issues
  end

  def test_deployment_hook_links_issue_via_sha_when_text_matching_finds_none
    project = Project.generate!(issue_key_prefix: 'AUTH')
    issue = Issue.generate!(project: project, subject: 'Trace target')
    @external_repository.update!(redmine_project: project)

    pull_request = ExternalPullRequest.create!(
      provider: 'gitlab',
      external_repository: @external_repository,
      number: 11,
      title: 'Trace MR',
      url: 'https://gitlab.example.com/redmine/redmine_dev_integration/-/merge_requests/11',
      state: 'open',
      merged: false,
      source_sha: 'abc123'
    )
    ExternalPullRequestIssue.create!(external_pull_request: pull_request, issue: issue)

    event = build_event(payload: JSON.generate({
      deployment_id: 9003,
      environment: 'production',
      environment_external_url: 'https://prod.example.test',
      status: 'success',
      sha: 'abc123',
      ref: 'main',
      commit_title: 'Release',
      user: {
        username: 'contributor',
        name: 'Contributor'
      },
      deployable_started_at: '2026-05-25T10:00:00Z',
      deployable_finished_at: '2026-05-25T10:20:00Z',
      created_at: '2026-05-25T10:00:00Z',
      updated_at: '2026-05-25T10:25:00Z',
      project: {
        id: 456,
        web_url: 'https://gitlab.example.com/redmine/redmine_dev_integration'
      }
    }))

    assert @processor.call(event)

    deployment = ExternalDeployment.find_by!(
      provider: 'gitlab',
      external_repository: @external_repository,
      provider_deployment_id: '9003',
      environment_name: 'production'
    )

    assert_equal [issue.id], deployment.issues.pluck(:id)
    assert_equal 1, deployment.external_deployment_issues.count
  end
end
