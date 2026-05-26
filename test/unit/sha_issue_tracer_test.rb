# frozen_string_literal: true

require_relative '../test_helper'

class ShaIssueTracerTest < ActiveSupport::TestCase
  fixtures :projects, :repositories

  def setup
    @tracer = RedmineDevIntegration::ShaIssueTracer.new
    @external_repository = ExternalRepository.create!(
      provider: 'github',
      provider_repository_id: '123',
      owner: 'redmine',
      repo_name: 'redmine_dev_integration',
      full_name: 'redmine/redmine_dev_integration',
      url: 'https://github.com/redmine/redmine_dev_integration',
      redmine_project: projects(:projects_001)
    )
    @project = Project.generate!(issue_key_prefix: 'AUTH')
    @external_repository.update!(redmine_project: @project)
  end

  def test_returns_distinct_issue_ids_for_source_target_and_merge_sha_matches
    issue_one = Issue.generate!(project: @project, subject: 'Source match')
    issue_two = Issue.generate!(project: @project, subject: 'Target match')
    issue_three = Issue.generate!(project: @project, subject: 'Merge match')

    source_pull_request = ExternalPullRequest.create!(
      provider: 'github',
      external_repository: @external_repository,
      number: 1,
      title: 'Source PR',
      url: 'https://github.com/redmine/redmine_dev_integration/pull/1',
      state: 'open',
      merged: false,
      source_sha: 'abc123'
    )
    ExternalPullRequestIssue.create!(external_pull_request: source_pull_request, issue: issue_one)

    source_pull_request_duplicate = ExternalPullRequest.create!(
      provider: 'github',
      external_repository: @external_repository,
      number: 4,
      title: 'Source PR duplicate',
      url: 'https://github.com/redmine/redmine_dev_integration/pull/4',
      state: 'open',
      merged: false,
      source_sha: 'abc123'
    )
    ExternalPullRequestIssue.create!(external_pull_request: source_pull_request_duplicate, issue: issue_one)

    target_pull_request = ExternalPullRequest.create!(
      provider: 'github',
      external_repository: @external_repository,
      number: 2,
      title: 'Target PR',
      url: 'https://github.com/redmine/redmine_dev_integration/pull/2',
      state: 'open',
      merged: false,
      target_sha: 'abc123'
    )
    ExternalPullRequestIssue.create!(external_pull_request: target_pull_request, issue: issue_two)

    merge_pull_request = ExternalPullRequest.create!(
      provider: 'github',
      external_repository: @external_repository,
      number: 3,
      title: 'Merge PR',
      url: 'https://github.com/redmine/redmine_dev_integration/pull/3',
      state: 'closed',
      merged: true,
      merge_commit_sha: 'abc123'
    )
    ExternalPullRequestIssue.create!(external_pull_request: merge_pull_request, issue: issue_three)

    assert_equal [issue_one.id, issue_two.id, issue_three.id].sort, @tracer.call(
      external_repository: @external_repository,
      sha: 'abc123'
    ).sort
  end

  def test_returns_empty_array_when_no_pull_request_matches_sha
    assert_equal [], @tracer.call(external_repository: @external_repository, sha: 'deadbeef')
  end
end
