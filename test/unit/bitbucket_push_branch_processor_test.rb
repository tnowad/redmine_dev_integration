# frozen_string_literal: true

require_relative '../test_helper'

class BitbucketPushBranchProcessorTest < ActiveSupport::TestCase
  fixtures :projects, :repositories

  def setup
    @processor = RedmineDevIntegration::BitbucketPushBranchProcessor.new
    @external_repository = ExternalRepository.create!(
      provider: 'bitbucket',
      provider_repository_id: 'my-repo',
      owner: 'my-workspace',
      repo_name: 'my-repo',
      full_name: 'my-workspace/my-repo',
      url: 'https://bitbucket.org/my-workspace/my-repo',
      redmine_project: projects(:projects_001)
    )
  end

  def build_push_event(attributes = {})
    ExternalProviderEvent.new({
      provider: 'bitbucket',
      delivery_id: "delivery-#{SecureRandom.hex(4)}",
      event_type: 'repo:push',
      payload: JSON.generate({
        push: {
          changes: []
        },
        repository: {
          full_name: 'my-workspace/my-repo',
          links: {
            html: {
              href: 'https://bitbucket.org/my-workspace/my-repo'
            }
          }
        }
      }),
      status: 'pending'
    }.merge(attributes))
  end

  def test_push_links_issues_from_commit_messages
    project = Project.generate!(issue_key_prefix: 'AUTH')
    issue = Issue.generate!(project: project, subject: 'Login fix')
    @external_repository.update!(redmine_project: project)

    event = build_push_event(payload: JSON.generate({
      push: {
        changes: [
          {
            new: {
              type: 'branch',
              name: 'feature',
              target: { hash: 'abc123' }
            },
            commits: [
              { hash: 'c1', message: "Fix ##{issue.issue_key} login issue" },
              { hash: 'c2', message: 'Cleanup whitespace' }
            ]
          }
        ]
      },
      repository: {
        full_name: 'my-workspace/my-repo',
        links: {
          html: {
            href: 'https://bitbucket.org/my-workspace/my-repo'
          }
        }
      }
    }))

    assert @processor.call(event)

    branch = ExternalBranch.find_by!(external_repository: @external_repository, name: 'feature')
    assert_equal [issue.id], branch.issues.pluck(:id)
    assert_equal 1, branch.external_branch_issues.count
  end

  def test_push_branch_name_still_links_issues
    project = Project.generate!(issue_key_prefix: 'AUTH')
    issue = Issue.generate!(project: project, subject: 'Repo setup')
    @external_repository.update!(redmine_project: project)

    event = build_push_event(payload: JSON.generate({
      push: {
        changes: [
          {
            new: {
              type: 'branch',
              name: "feature/#{issue.issue_key}-setup",
              target: { hash: 'abc123' }
            },
            commits: []
          }
        ]
      },
      repository: {
        full_name: 'my-workspace/my-repo',
        links: {
          html: {
            href: 'https://bitbucket.org/my-workspace/my-repo'
          }
        }
      }
    }))

    assert @processor.call(event)

    branch = ExternalBranch.find_by!(external_repository: @external_repository, name: "feature/#{issue.issue_key}-setup")
    assert_equal [issue.id], branch.issues.pluck(:id)
  end

  def test_push_with_no_commits_does_not_fail
    project = Project.generate!(issue_key_prefix: 'AUTH')
    @external_repository.update!(redmine_project: project)

    event = build_push_event(payload: JSON.generate({
      push: {
        changes: [
          {
            new: {
              type: 'branch',
              name: 'feature',
              target: { hash: 'abc123' }
            },
            commits: nil
          }
        ]
      },
      repository: {
        full_name: 'my-workspace/my-repo',
        links: {
          html: {
            href: 'https://bitbucket.org/my-workspace/my-repo'
          }
        }
      }
    }))

    assert @processor.call(event)
    branch = ExternalBranch.find_by!(external_repository: @external_repository, name: 'feature')
    assert_empty branch.issues
  end

  def test_push_with_multiple_changes_links_each_separately
    project = Project.generate!(issue_key_prefix: 'AUTH')
    issue1 = Issue.generate!(project: project, subject: 'First')
    issue2 = Issue.generate!(project: project, subject: 'Second')
    @external_repository.update!(redmine_project: project)

    event = build_push_event(payload: JSON.generate({
      push: {
        changes: [
          {
            new: {
              type: 'branch',
              name: 'feature-one',
              target: { hash: 'abc123' }
            },
            commits: [
              { hash: 'c1', message: "Fix #{issue1.issue_key}" }
            ]
          },
          {
            new: {
              type: 'branch',
              name: 'feature-two',
              target: { hash: 'def456' }
            },
            commits: [
              { hash: 'c2', message: "Fix #{issue2.issue_key}" }
            ]
          }
        ]
      },
      repository: {
        full_name: 'my-workspace/my-repo',
        links: {
          html: {
            href: 'https://bitbucket.org/my-workspace/my-repo'
          }
        }
      }
    }))

    assert @processor.call(event)

    branch1 = ExternalBranch.find_by!(external_repository: @external_repository, name: 'feature-one')
    branch2 = ExternalBranch.find_by!(external_repository: @external_repository, name: 'feature-two')
    assert_equal [issue1.id], branch1.issues.pluck(:id)
    assert_equal [issue2.id], branch2.issues.pluck(:id)
  end
end
