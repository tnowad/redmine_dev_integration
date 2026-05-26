# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/dev_integration_test_factory'

class CrossPluginTest < Redmine::IntegrationTest
  include DevIntegrationTestFactory

  setup do
    @project = Project.generate!
    @project.update_column(:issue_key_prefix, 'DEV')
    @issue = Issue.generate!(project: @project, subject: 'Test E2E', author: User.find(1))
    @issue.reload
    @repo = create_external_repository(project: @project)
  end

  def test_issue_linker_resolves_keys_when_redmine_issue_keys_is_installed
    assert Issue.respond_to?(:find_by_issue_key)

    linker = RedmineDevIntegration::IssueLinker.new
    result = linker.link(["#{@issue.issue_key}", "feature/#{@issue.issue_key}-login"])

    assert_includes result.issue_ids, @issue.id
    assert_includes result.matched_keys, @issue.issue_key
  end

  def test_issue_linker_resolves_multiple_keys
    issue2 = Issue.generate!(project: @project, subject: 'Second issue', author: User.find(1))
    issue2.reload

    linker = RedmineDevIntegration::IssueLinker.new
    result = linker.link(["#{@issue.issue_key} and #{issue2.issue_key}"])

    assert_includes result.issue_ids, @issue.id
    assert_includes result.issue_ids, issue2.id
  end

  def test_issue_linker_returns_empty_when_redmine_issue_keys_not_installed
    Issue.stubs(:respond_to?).with(:find_by_issue_key).returns(false)

    linker = RedmineDevIntegration::IssueLinker.new
    result = linker.link(["#{@issue.issue_key}"])

    assert_empty result.issue_ids
    assert_equal [@issue.issue_key], result.matched_keys
  end

  def test_branch_links_to_issue_via_link_issues_from_texts
    branch = ExternalBranch.create!(
      external_repository: @repo,
      name: "feature/#{@issue.issue_key}-login",
      url: 'https://github.com/owner/repo/tree/feature',
      sha: 'abc123',
      state: 'active'
    )
    branch.link_issues_from_texts(branch.name, "fixes #{@issue.issue_key}")

    assert branch.issues.include?(@issue)
    assert_equal 1, branch.external_branch_issues.count
  end

  def test_pr_links_to_issue_via_link_issues_from_texts
    pr = ExternalPullRequest.create!(
      provider: 'github',
      external_repository: @repo,
      number: 1,
      title: "Fix #{@issue.issue_key}",
      body: 'PR body with fixes',
      url: 'https://github.com/owner/repo/pull/1',
      state: 'open',
      author_login: 'dev',
      source_branch: 'feature/fix',
      target_branch: 'main',
      merged: false,
      opened_at: Time.current
    )
    pr.link_issues_from_texts(pr.title, pr.body)

    assert pr.issues.include?(@issue)
    assert_equal 1, pr.external_pull_request_issues.count
  end

  def test_changeset_links_to_issue_via_changeset_issue_key_linker
    Setting.stubs(:commit_cross_project_ref?).returns(true)

    repo = Repository::Git.create!(project: @project, url: '/tmp/test.git')
    changeset = Changeset.create!(
      repository: repo,
      revision: 'abc123',
      committer: 'dev',
      committed_on: Time.now,
      comments: "refs #{@issue.issue_key}"
    )
    RedmineDevIntegration::SmartCommitService.stubs(:call)

    RedmineDevIntegration::ChangesetIssueKeyLinker.new.call(changeset: changeset)
    changeset.reload

    assert changeset.issues.include?(@issue), "Changeset should be linked to issue via issue key"
  end

  def test_changeset_issue_key_linker_excludes_issues_from_other_projects_when_cross_project_disabled
    Setting.stubs(:commit_cross_project_ref?).returns(false)

    other_project = Project.generate!
    other_issue = Issue.generate!(project: other_project, subject: 'Other', author: User.find(1))

    repo = Repository::Git.create!(project: @project, url: '/tmp/test2.git')
    changeset = Changeset.create!(
      repository: repo,
      revision: 'def456',
      committer: 'dev',
      committed_on: Time.now,
      comments: "refs #{@issue.issue_key} and #{other_issue.issue_key}"
    )
    RedmineDevIntegration::SmartCommitService.stubs(:call)

    RedmineDevIntegration::ChangesetIssueKeyLinker.new.call(changeset: changeset)
    changeset.reload

    assert changeset.issues.include?(@issue), "Own project issue should be linked"
    assert_not changeset.issues.include?(other_issue), "Cross-project issue should be excluded"
  end

  def test_dev_panel_data_factory_generates_linked_objects
    panel_data = create_dev_panel_data(issue: @issue, repository: @repo)

    assert_not_nil panel_data[:branch]
    assert_not_nil panel_data[:pull_request]
    assert_not_nil panel_data[:build]
    assert_not_nil panel_data[:deployment]

    assert panel_data[:branch].issues.include?(@issue)
    assert panel_data[:pull_request].issues.include?(@issue)
    assert panel_data[:build].issues.include?(@issue)
    assert panel_data[:deployment].issues.include?(@issue)
  end
end
