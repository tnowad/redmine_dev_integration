# frozen_string_literal: true

require_relative '../test_helper'

class BitbucketDeploymentProcessorTest < ActiveSupport::TestCase
  fixtures :projects, :repositories

  def setup
    @processor = RedmineDevIntegration::BitbucketDeploymentProcessor.new
    @external_repository = ExternalRepository.create!(
      provider: 'bitbucket',
      provider_repository_id: 'my-repo-uuid',
      owner: 'my-workspace',
      repo_name: 'my-repo',
      full_name: 'my-workspace/my-repo',
      url: 'https://bitbucket.org/my-workspace/my-repo',
      redmine_project: projects(:projects_001)
    )
  end

  def build_event(attributes = {})
    ExternalProviderEvent.new({
      provider: 'bitbucket',
      delivery_id: "delivery-#{SecureRandom.hex(4)}",
      event_type: 'repo:deployment',
      payload: JSON.generate({
        repository: {
          uuid: 'my-repo-uuid',
          full_name: 'my-workspace/my-repo'
        },
        deployment: {
          uuid: 'deploy-9001',
          environment: {
            name: 'staging'
          },
          state: {
            name: 'IN_PROGRESS'
          },
          release: {
            name: 'main',
            commit: 'abc123',
            url: 'https://staging.example.test'
          },
          comment: 'Deploy to staging',
          deployer: {
            username: 'contributor',
            display_name: 'Contributor'
          },
          created_on: '2026-05-25T10:00:00Z',
          started_on: '2026-05-25T10:00:00Z',
          completed_on: nil,
          updated_on: '2026-05-25T10:05:00Z'
        }
      }),
      status: 'pending'
    }.merge(attributes))
  end

  def test_deployment_success_creates_external_deployment
    project = Project.generate!(issue_key_prefix: 'AUTH')
    issue = Issue.generate!(project: project, subject: 'Deployment target')
    @external_repository.update!(redmine_project: project)

    event = build_event(payload: JSON.generate({
      repository: {
        uuid: 'my-repo-uuid',
        full_name: 'my-workspace/my-repo'
      },
      deployment: {
        uuid: 'deploy-9001',
        environment: {
          name: 'staging'
        },
        state: {
          name: 'COMPLETED',
          result: {
            name: 'SUCCESSFUL'
          }
        },
        release: {
          name: "feature/#{issue.issue_key}-login",
          commit: 'abc123',
          url: 'https://staging.example.test'
        },
        comment: "Deploy #{issue.issue_key} to staging",
        deployer: {
          username: 'contributor',
          display_name: 'Contributor'
        },
        created_on: '2026-05-25T10:00:00Z',
        started_on: '2026-05-25T10:00:00Z',
        completed_on: '2026-05-25T10:20:00Z',
        updated_on: '2026-05-25T10:25:00Z'
      }
    }))

    assert @processor.call(event)

    deployment = ExternalDeployment.find_by!(
      provider: 'bitbucket',
      external_repository: @external_repository,
      provider_deployment_id: 'deploy-9001',
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

  def test_deployment_failure_creates_external_deployment
    project = Project.generate!(issue_key_prefix: 'AUTH')
    issue = Issue.generate!(project: project, subject: 'Failure test')
    @external_repository.update!(redmine_project: project)

    event = build_event(payload: JSON.generate({
      repository: {
        uuid: 'my-repo-uuid',
        full_name: 'my-workspace/my-repo'
      },
      deployment: {
        uuid: 'deploy-9002',
        environment: {
          name: 'production'
        },
        state: {
          name: 'COMPLETED',
          result: {
            name: 'FAILED'
          }
        },
        release: {
          name: "fix/#{issue.issue_key}-crash",
          commit: 'def456',
          url: 'https://prod.example.test'
        },
        comment: "Failed #{issue.issue_key} deploy",
        deployer: {
          username: 'contributor',
          display_name: 'Contributor'
        },
        created_on: '2026-05-25T10:00:00Z',
        started_on: '2026-05-25T10:00:00Z',
        completed_on: '2026-05-25T10:15:00Z',
        updated_on: '2026-05-25T10:20:00Z'
      }
    }))

    assert @processor.call(event)

    deployment = ExternalDeployment.find_by!(
      provider: 'bitbucket',
      external_repository: @external_repository,
      provider_deployment_id: 'deploy-9002',
      environment_name: 'production'
    )

    assert_equal 'failed', deployment.status
    assert_equal 'def456', deployment.sha
    assert_equal "fix/#{issue.issue_key}-crash", deployment.ref
    assert_equal "Failed #{issue.issue_key} deploy", deployment.description
    assert_equal [issue.id], deployment.issues.pluck(:id)
  end

  def test_issue_linking_from_deployment_text
    project = Project.generate!(issue_key_prefix: 'AUTH')
    issue1 = Issue.generate!(project: project, subject: 'First issue')
    issue2 = Issue.generate!(project: project, subject: 'Second issue')
    @external_repository.update!(redmine_project: project)

    event = build_event(payload: JSON.generate({
      repository: {
        uuid: 'my-repo-uuid',
        full_name: 'my-workspace/my-repo'
      },
      deployment: {
        uuid: 'deploy-9003',
        environment: {
          name: 'staging'
        },
        state: {
          name: 'COMPLETED',
          result: {
            name: 'SUCCESSFUL'
          }
        },
        release: {
          name: "deploy/#{issue1.issue_key}-#{issue2.issue_key}",
          commit: 'abc123',
          url: 'https://staging.example.test'
        },
        comment: "Deploy #{issue1.issue_key} and #{issue2.issue_key}",
        deployer: {
          username: 'contributor'
        },
        created_on: '2026-05-25T10:00:00Z',
        started_on: '2026-05-25T10:00:00Z',
        completed_on: '2026-05-25T10:20:00Z',
        updated_on: '2026-05-25T10:25:00Z'
      }
    }))

    assert @processor.call(event)

    deployment = ExternalDeployment.find_by!(
      provider: 'bitbucket',
      external_repository: @external_repository,
      provider_deployment_id: 'deploy-9003',
      environment_name: 'staging'
    )

    assert_equal [issue1.id, issue2.id].sort, deployment.issues.pluck(:id).sort
    assert_equal 2, deployment.external_deployment_issues.count
  end

  def test_unknown_issue_key_does_not_fail
    event = build_event(payload: JSON.generate({
      repository: {
        uuid: 'my-repo-uuid',
        full_name: 'my-workspace/my-repo'
      },
      deployment: {
        uuid: 'deploy-9004',
        environment: {
          name: 'production'
        },
        state: {
          name: 'COMPLETED',
          result: {
            name: 'SUCCESSFUL'
          }
        },
        release: {
          name: "deploy/AUTH-9999",
          commit: 'abc123',
          url: 'https://prod.example.test'
        },
        comment: 'Deploy AUTH-9999 to production',
        deployer: {
          username: 'contributor'
        },
        created_on: '2026-05-25T10:00:00Z',
        started_on: '2026-05-25T10:00:00Z',
        completed_on: '2026-05-25T10:20:00Z',
        updated_on: '2026-05-25T10:25:00Z'
      }
    }))

    assert_nothing_raised do
      assert @processor.call(event)
    end

    deployment = ExternalDeployment.find_by!(
      provider: 'bitbucket',
      external_repository: @external_repository,
      provider_deployment_id: 'deploy-9004',
      environment_name: 'production'
    )
    assert_empty deployment.issues
  end

  def test_duplicate_event_updates_existing_deployment
    first_event = build_event(payload: JSON.generate({
      repository: {
        uuid: 'my-repo-uuid',
        full_name: 'my-workspace/my-repo'
      },
      deployment: {
        uuid: 'deploy-9005',
        environment: {
          name: 'staging'
        },
        state: {
          name: 'IN_PROGRESS'
        },
        release: {
          name: 'main',
          commit: 'abc123',
          url: 'https://staging.example.test'
        },
        comment: 'Deploy to staging',
        deployer: {
          username: 'contributor'
        },
        created_on: '2026-05-25T10:00:00Z',
        started_on: '2026-05-25T10:00:00Z',
        completed_on: nil,
        updated_on: '2026-05-25T10:05:00Z'
      }
    }))

    second_event = build_event(payload: JSON.generate({
      repository: {
        uuid: 'my-repo-uuid',
        full_name: 'my-workspace/my-repo'
      },
      deployment: {
        uuid: 'deploy-9005',
        environment: {
          name: 'staging'
        },
        state: {
          name: 'FAILED'
        },
        release: {
          name: 'main',
          commit: 'def456',
          url: 'https://staging.example.test'
        },
        comment: 'Deploy to staging',
        deployer: {
          username: 'contributor'
        },
        created_on: '2026-05-25T10:00:00Z',
        started_on: '2026-05-25T10:00:00Z',
        completed_on: '2026-05-25T11:00:00Z',
        updated_on: '2026-05-25T11:05:00Z'
      }
    }))

    assert @processor.call(first_event)
    assert @processor.call(second_event)

    assert_equal 1, ExternalDeployment.where(
      provider: 'bitbucket',
      external_repository: @external_repository,
      provider_deployment_id: 'deploy-9005',
      environment_name: 'staging'
    ).count

    deployment = ExternalDeployment.find_by!(
      provider: 'bitbucket',
      external_repository: @external_repository,
      provider_deployment_id: 'deploy-9005',
      environment_name: 'staging'
    )

    assert_equal 'failed', deployment.status
    assert_equal 'def456', deployment.sha
    assert_equal Time.zone.parse('2026-05-25T11:00:00Z'), deployment.completed_at
    assert_equal Time.zone.parse('2026-05-25T11:05:00Z'), deployment.last_event_at
  end

  def test_unsupported_event_type_returns_false
    event = ExternalProviderEvent.new(
      provider: 'bitbucket',
      delivery_id: "delivery-#{SecureRandom.hex(4)}",
      event_type: 'repo:push',
      payload: JSON.generate({
        repository: {
          uuid: 'my-repo-uuid',
          full_name: 'my-workspace/my-repo'
        },
        push: {
          changes: []
        }
      }),
      status: 'pending'
    )

    assert_equal false, @processor.call(event)
    assert_nil ExternalDeployment.find_by(provider: 'bitbucket', provider_deployment_id: 'deploy-9001')
  end

  def test_missing_repository_is_ignored_without_error
    event = build_event(payload: JSON.generate({
      repository: {
        uuid: 'other-repo-uuid',
        full_name: 'other-workspace/other-repo'
      },
      deployment: {
        uuid: 'deploy-9006',
        environment: {
          name: 'staging'
        },
        state: {
          name: 'COMPLETED',
          result: {
            name: 'SUCCESSFUL'
          }
        },
        release: {
          name: 'main',
          commit: 'abc123',
          url: 'https://staging.example.test'
        },
        comment: 'Deploy AUTH-9999 to staging',
        deployer: {
          username: 'contributor'
        },
        created_on: '2026-05-25T10:00:00Z',
        started_on: '2026-05-25T10:00:00Z',
        completed_on: '2026-05-25T10:20:00Z',
        updated_on: '2026-05-25T10:25:00Z'
      }
    }))

    refute @processor.call(event)
    assert_nil ExternalDeployment.find_by(provider: 'bitbucket', provider_deployment_id: 'deploy-9006')
  end

  def test_deployment_links_issue_via_sha_when_text_matching_finds_none
    project = Project.generate!(issue_key_prefix: 'AUTH')
    issue = Issue.generate!(project: project, subject: 'Trace target')
    @external_repository.update!(redmine_project: project)

    pull_request = ExternalPullRequest.create!(
      provider: 'bitbucket',
      external_repository: @external_repository,
      number: 11,
      title: 'Trace PR',
      url: 'https://bitbucket.org/my-workspace/my-repo/pull-requests/11',
      state: 'open',
      merged: false,
      source_sha: 'abc123'
    )
    ExternalPullRequestIssue.create!(external_pull_request: pull_request, issue: issue)

    event = build_event(payload: JSON.generate({
      repository: {
        uuid: 'my-repo-uuid',
        full_name: 'my-workspace/my-repo'
      },
      deployment: {
        uuid: 'deploy-9007',
        environment: {
          name: 'production'
        },
        state: {
          name: 'COMPLETED',
          result: {
            name: 'SUCCESSFUL'
          }
        },
        release: {
          name: 'main',
          commit: 'abc123',
          url: 'https://prod.example.test'
        },
        comment: 'Release',
        deployer: {
          username: 'contributor'
        },
        created_on: '2026-05-25T10:00:00Z',
        started_on: '2026-05-25T10:00:00Z',
        completed_on: '2026-05-25T10:20:00Z',
        updated_on: '2026-05-25T10:25:00Z'
      }
    }))

    assert @processor.call(event)

    deployment = ExternalDeployment.find_by!(
      provider: 'bitbucket',
      external_repository: @external_repository,
      provider_deployment_id: 'deploy-9007',
      environment_name: 'production'
    )

    assert_equal [issue.id], deployment.issues.pluck(:id)
    assert_equal 1, deployment.external_deployment_issues.count
  end
end
