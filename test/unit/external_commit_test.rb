# frozen_string_literal: true

require_relative '../test_helper'

class ExternalCommitTest < ActiveSupport::TestCase
  fixtures :projects, :repositories

  def setup
    @external_repository = ExternalRepository.new(
      provider: 'github',
      provider_repository_id: '123',
      owner: 'redmine',
      repo_name: 'redmine_dev_integration',
      full_name: 'redmine/redmine_dev_integration',
      url: 'https://github.com/redmine/redmine_dev_integration',
      redmine_project: projects(:projects_001)
    )
    @external_repository.save!

    @external_commit = ExternalCommit.new(
      provider: 'github',
      external_repository: @external_repository,
      provider_commit_id: 'abc123def456',
      sha: 'abc123def456',
      short_sha: 'abc123d',
      message: 'Fix login issue',
      author_login: 'contributor',
      author_name: 'Contributor',
      url: 'https://github.com/redmine/redmine_dev_integration/commit/abc123def456',
      branch_name: 'main',
      committed_at: Time.current,
      last_event_at: Time.current
    )
  end

  def test_valid_record
    assert_predicate @external_commit, :valid?
  end

  def test_requires_presence_of_core_attributes
    @external_commit.provider = nil
    @external_commit.external_repository = nil
    @external_commit.provider_commit_id = nil
    @external_commit.sha = nil
    @external_commit.message = nil
    @external_commit.committed_at = nil

    assert_not_predicate @external_commit, :valid?
    %i[provider external_repository provider_commit_id sha message].each do |attribute|
      assert @external_commit.errors[attribute].present?, "expected #{attribute} to be invalid"
    end
  end

  def test_enforces_uniqueness_of_provider_commit_id_per_provider_and_external_repository
    @external_commit.save!

    duplicate = @external_commit.dup
    assert_not_predicate duplicate, :valid?
    assert_includes duplicate.errors[:provider_commit_id], 'has already been taken'
  end

  def test_allows_same_provider_commit_id_across_different_providers
    @external_commit.save!

    other_repo = ExternalRepository.create!(
      provider: 'gitlab',
      provider_repository_id: '456',
      owner: 'gitlab-org',
      repo_name: 'test',
      full_name: 'gitlab-org/test',
      url: 'https://gitlab.com/gitlab-org/test',
      redmine_project: projects(:projects_001)
    )
    other = @external_commit.dup
    other.provider = 'gitlab'
    other.external_repository = other_repo

    assert_predicate other, :valid?
  end

  def test_links_issues_from_messages_and_deduplicates
    project = Project.generate!(issue_key_prefix: 'AUTH')
    @external_repository.update!(redmine_project: project)
    issue_one = Issue.generate!(project: project, subject: 'One')
    issue_two = Issue.generate!(project: project, subject: 'Two')
    @external_commit.save!

    result = @external_commit.link_issues_from_texts(
      "#{issue_one.issue_key}: Login",
      "#{issue_two.issue_key}: Docs"
    )

    assert_equal [issue_one.issue_key, issue_two.issue_key], result.matched_keys
    assert_equal [issue_one.id, issue_two.id], result.issue_ids
    assert_equal [issue_one.id, issue_two.id], @external_commit.reload.issues.pluck(:id)

    assert_difference 'ExternalCommitIssue.count', 0 do
      @external_commit.link_issues_from_texts("#{issue_one.issue_key} #{issue_two.issue_key} #{issue_one.issue_key}")
    end
    assert_equal 2, @external_commit.external_commit_issues.count
  end

  def test_links_only_issues_from_mapped_project_and_ignores_unknown_keys
    project = Project.generate!(issue_key_prefix: 'AUTH')
    other_project = Project.generate!(issue_key_prefix: 'OPS')
    @external_repository.update!(redmine_project: project)
    issue = Issue.generate!(project: project, subject: 'Login fix')
    other_issue = Issue.generate!(project: other_project, subject: 'Other fix')
    @external_commit.save!

    assert_nothing_raised do
      result = @external_commit.link_issues_from_texts("#{issue.issue_key} #{other_issue.issue_key} AUTH-9999")
      assert_equal [issue.issue_key, other_issue.issue_key, 'AUTH-9999'], result.matched_keys
      assert_equal [issue.id, other_issue.id], result.issue_ids
    end

    assert_equal [issue.id], @external_commit.reload.issues.pluck(:id)
    assert_equal [issue.id], @external_commit.external_commit_issues.pluck(:issue_id)
  end
end
