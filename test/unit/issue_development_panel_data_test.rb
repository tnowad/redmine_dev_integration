# frozen_string_literal: true

require_relative '../test_helper'

class IssueDevelopmentPanelDataTest < ActiveSupport::TestCase
  fixtures :projects, :repositories, :users

  def setup
    @project = Project.generate!(issue_key_prefix: 'AUTH')
    @other_project = Project.generate!(issue_key_prefix: 'OPS')
    @issue = Issue.generate!(project: @project, subject: 'Tracked issue')

    @repository = repositories(:repositories_001)
    @repository.update!(project: @project)
    @external_repository = ExternalRepository.create!(
      provider: 'github',
      provider_repository_id: '123',
      owner: 'redmine',
      repo_name: 'redmine_dev_integration',
      full_name: 'redmine/redmine_dev_integration',
      url: 'https://github.com/redmine/redmine_dev_integration',
      redmine_project: @project,
      redmine_repository: @repository
    )
    @other_external_repository = ExternalRepository.create!(
      provider: 'github',
      provider_repository_id: '456',
      owner: 'redmine',
      repo_name: 'other_repo',
      full_name: 'redmine/other_repo',
      url: 'https://github.com/redmine/other_repo',
      redmine_project: @other_project
    )
  end

  def test_returns_branches_and_pull_requests_for_issue_scoped_to_project
    branch = ExternalBranch.create!(
      external_repository: @external_repository,
      name: 'main',
      url: 'https://github.com/redmine/redmine_dev_integration/tree/main',
      sha: 'abc123',
      state: 'active'
    )
    branch.link_issues_from_texts(@issue.issue_key)

    pull_request = ExternalPullRequest.create!(
      provider: 'github',
      external_repository: @external_repository,
      number: 7,
      title: 'Fix tracked issue',
      body: nil,
      url: 'https://github.com/redmine/redmine_dev_integration/pull/7',
      state: 'open',
      merged: false
    )
    pull_request.link_issues_from_texts(@issue.issue_key)

    other_branch = ExternalBranch.create!(
      external_repository: @other_external_repository,
      name: 'main',
      url: 'https://github.com/redmine/other_repo/tree/main',
      sha: 'def456',
      state: 'active'
    )
    other_branch.link_issues_from_texts(@issue.issue_key)

    data = RedmineDevIntegration::IssueDevelopmentPanelData.new(@issue)

    assert_equal [branch.id], data.branches.pluck(:id)
    assert_equal [pull_request.id], data.pull_requests.pluck(:id)
  end

  def test_excludes_deleted_branches
    active_branch = ExternalBranch.create!(
      external_repository: @external_repository,
      name: 'active',
      url: 'https://github.com/redmine/redmine_dev_integration/tree/active',
      sha: 'abc123',
      state: 'active'
    )
    deleted_branch = ExternalBranch.create!(
      external_repository: @external_repository,
      name: 'deleted',
      url: 'https://github.com/redmine/redmine_dev_integration/tree/deleted',
      sha: 'def456',
      state: 'deleted',
      deleted_at: Time.current
    )
    active_branch.link_issues_from_texts(@issue.issue_key)
    deleted_branch.link_issues_from_texts(@issue.issue_key)

    data = RedmineDevIntegration::IssueDevelopmentPanelData.new(@issue)

    assert_equal [active_branch.id], data.branches.pluck(:id)
  end

  def test_returns_empty_commits_for_issue_without_associated_changesets
    data = RedmineDevIntegration::IssueDevelopmentPanelData.new(@issue)

    assert_empty data.commits
  end

  def test_returns_visible_commits_for_issue
    repository = repositories(:repositories_001)
    changeset = repository.changesets.create!(
      user_id: users(:users_002).id,
      revision: '12345',
      committed_on: Time.current,
      comments: 'Fixes #1'
    )
    @issue.changesets << changeset

    data = RedmineDevIntegration::IssueDevelopmentPanelData.new(@issue)

    assert_equal [changeset.id], data.commits.pluck(:id)
  end

  def test_returns_builds_and_deployments_for_issue_scoped_to_project_newest_first
    event_time = Time.zone.parse('2026-05-25 10:00:00 UTC')

    build_older = ExternalBuild.create!(
      provider: 'github',
      external_repository: @external_repository,
      provider_build_id: '101',
      build_number: 101,
      name: 'Build 101',
      status: 'success',
      url: 'https://github.com/redmine/redmine_dev_integration/actions/runs/101',
      sha: '0123456789abcdef',
      ref: 'main',
      started_at: event_time - 30.minutes,
      finished_at: event_time - 5.minutes,
      last_event_at: event_time
    )
    build_newer = ExternalBuild.create!(
      provider: 'github',
      external_repository: @external_repository,
      provider_build_id: '102',
      build_number: 102,
      name: 'Build 102',
      status: 'in_progress',
      url: 'https://github.com/redmine/redmine_dev_integration/actions/runs/102',
      sha: 'fedcba9876543210',
      ref: 'feature/auth',
      started_at: event_time - 15.minutes,
      finished_at: nil,
      last_event_at: event_time
    )
    build_older.update_columns(updated_at: event_time - 2.hours)
    build_newer.update_columns(updated_at: event_time - 1.hour)
    build_older.link_issues_from_texts(@issue.issue_key)
    build_newer.link_issues_from_texts(@issue.issue_key)

    other_build = ExternalBuild.create!(
      provider: 'github',
      external_repository: @other_external_repository,
      provider_build_id: '201',
      build_number: 201,
      name: 'Other build',
      status: 'success',
      url: 'https://github.com/redmine/other_repo/actions/runs/201',
      sha: 'aaaaaaaaaaaaaaaa',
      ref: 'main',
      started_at: event_time,
      finished_at: event_time,
      last_event_at: event_time + 1.hour
    )
    ExternalBuildIssue.create!(external_build: other_build, issue: @issue)

    deployment_older = ExternalDeployment.create!(
      provider: 'github',
      external_repository: @external_repository,
      provider_deployment_id: '301',
      environment_name: 'staging',
      environment_url: 'https://staging.example.test',
      status: 'success',
      sha: '0123456789abcdef',
      ref: 'main',
      started_at: event_time - 45.minutes,
      completed_at: event_time - 10.minutes,
      last_event_at: event_time
    )
    deployment_newer = ExternalDeployment.create!(
      provider: 'github',
      external_repository: @external_repository,
      provider_deployment_id: '302',
      environment_name: 'production',
      environment_url: 'https://prod.example.test',
      status: 'in_progress',
      sha: 'fedcba9876543210',
      ref: 'release/1.0',
      started_at: event_time - 20.minutes,
      completed_at: nil,
      last_event_at: event_time
    )
    deployment_older.update_columns(updated_at: event_time - 2.hours)
    deployment_newer.update_columns(updated_at: event_time - 1.hour)
    deployment_older.link_issues_from_texts(@issue.issue_key)
    deployment_newer.link_issues_from_texts(@issue.issue_key)

    other_deployment = ExternalDeployment.create!(
      provider: 'github',
      external_repository: @other_external_repository,
      provider_deployment_id: '401',
      environment_name: 'preview',
      environment_url: 'https://preview.example.test',
      status: 'success',
      sha: 'bbbbbbbbbbbbbbbb',
      ref: 'main',
      started_at: event_time,
      completed_at: event_time,
      last_event_at: event_time + 1.hour
    )
    ExternalDeploymentIssue.create!(external_deployment: other_deployment, issue: @issue)

    data = RedmineDevIntegration::IssueDevelopmentPanelData.new(@issue)

    assert_equal [build_newer.id, build_older.id], data.builds.pluck(:id)
    assert_equal [deployment_newer.id, deployment_older.id], data.deployments.pluck(:id)
  end

  def test_orders_branches_and_pull_requests_by_repository_then_name_or_number
    repo_a = ExternalRepository.create!(
      provider: 'github',
      provider_repository_id: '234',
      owner: 'redmine',
      repo_name: 'aaa_repo',
      full_name: 'redmine/aaa_repo',
      url: 'https://github.com/redmine/aaa_repo',
      redmine_project: @project,
      redmine_repository: @repository
    )
    repo_b = ExternalRepository.create!(
      provider: 'github',
      provider_repository_id: '235',
      owner: 'redmine',
      repo_name: 'zzz_repo',
      full_name: 'redmine/zzz_repo',
      url: 'https://github.com/redmine/zzz_repo',
      redmine_project: @project,
      redmine_repository: @repository
    )

    branch_b2 = ExternalBranch.create!(external_repository: repo_b, name: 'b', url: nil, sha: '1', state: 'active')
    branch_a1 = ExternalBranch.create!(external_repository: repo_a, name: 'z', url: nil, sha: '1', state: 'active')
    branch_a0 = ExternalBranch.create!(external_repository: repo_a, name: 'a', url: nil, sha: '1', state: 'active')
    [branch_b2, branch_a1, branch_a0].each { |branch| branch.link_issues_from_texts(@issue.issue_key) }

    pr_b2 = ExternalPullRequest.create!(
      provider: 'github',
      external_repository: repo_b,
      number: 2,
      title: 'B',
      body: nil,
      url: 'https://github.com/redmine/zzz_repo/pull/2',
      state: 'open',
      merged: false
    )
    pr_a1 = ExternalPullRequest.create!(
      provider: 'github',
      external_repository: repo_a,
      number: 2,
      title: 'A2',
      body: nil,
      url: 'https://github.com/redmine/aaa_repo/pull/2',
      state: 'open',
      merged: false
    )
    pr_a0 = ExternalPullRequest.create!(
      provider: 'github',
      external_repository: repo_a,
      number: 1,
      title: 'A1',
      body: nil,
      url: 'https://github.com/redmine/aaa_repo/pull/1',
      state: 'open',
      merged: false
    )
    [pr_b2, pr_a1, pr_a0].each { |pr| pr.link_issues_from_texts(@issue.issue_key) }

    data = RedmineDevIntegration::IssueDevelopmentPanelData.new(@issue)

    assert_equal [branch_a0.id, branch_a1.id, branch_b2.id], data.branches.pluck(:id)
    assert_equal [pr_a0.id, pr_a1.id, pr_b2.id], data.pull_requests.pluck(:id)
  end
end
