# frozen_string_literal: true

require_relative '../test_helper'

class GitlabPushBranchProcessorTest < ActiveSupport::TestCase
  fixtures :projects, :repositories

  def setup
    @processor = RedmineDevIntegration::GitlabPushBranchProcessor.new
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

  def build_push_event(attributes = {})
    ExternalProviderEvent.new({
      provider: 'gitlab',
      delivery_id: "delivery-#{SecureRandom.hex(4)}",
      event_type: 'Push Hook',
      payload: JSON.generate({
        ref: 'refs/heads/main',
        before: '0000000000000000000000000000000000000000',
        after: 'abc123',
        project: {
          id: 456,
          web_url: 'https://gitlab.example.com/redmine/redmine_dev_integration'
        },
        commits: []
      }),
      status: 'pending'
    }.merge(attributes))
  end

  def test_push_links_issues_from_commit_messages
    project = Project.generate!(issue_key_prefix: 'AUTH')
    issue = Issue.generate!(project: project, subject: 'Login fix')
    @external_repository.update!(redmine_project: project)

    event = build_push_event(payload: JSON.generate({
      ref: 'refs/heads/feature',
      before: '0000000000000000000000000000000000000000',
      after: 'abc123',
      project: {
        id: 456,
        web_url: 'https://gitlab.example.com/redmine/redmine_dev_integration'
      },
      commits: [
        { id: 'c1', message: "Fix ##{issue.issue_key} login issue" },
        { id: 'c2', message: 'Cleanup whitespace' }
      ]
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
      ref: "refs/heads/feature/#{issue.issue_key}-setup",
      before: '0000000000000000000000000000000000000000',
      after: 'abc123',
      project: {
        id: 456,
        web_url: 'https://gitlab.example.com/redmine/redmine_dev_integration'
      },
      commits: []
    }))

    assert @processor.call(event)

    branch = ExternalBranch.find_by!(external_repository: @external_repository, name: "feature/#{issue.issue_key}-setup")
    assert_equal [issue.id], branch.issues.pluck(:id)
  end

  def test_push_with_no_commits_does_not_fail
    project = Project.generate!(issue_key_prefix: 'AUTH')
    @external_repository.update!(redmine_project: project)

    event = build_push_event(payload: JSON.generate({
      ref: 'refs/heads/feature',
      before: '0000000000000000000000000000000000000000',
      after: 'abc123',
      project: {
        id: 456,
        web_url: 'https://gitlab.example.com/redmine/redmine_dev_integration'
      },
      commits: nil
    }))

    assert @processor.call(event)
    branch = ExternalBranch.find_by!(external_repository: @external_repository, name: 'feature')
    assert_empty branch.issues
  end
end
