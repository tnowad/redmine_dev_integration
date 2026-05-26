# frozen_string_literal: true

require_relative '../test_helper'

class ExternalPullRequestTest < ActiveSupport::TestCase
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

    @external_pull_request = ExternalPullRequest.new(
      provider: 'github',
      external_repository: @external_repository,
      number: 1,
      title: 'Add feature',
      body: 'Pull request body',
      url: 'https://github.com/redmine/redmine_dev_integration/pull/1',
      state: 'open',
      author_login: 'contributor',
      source_branch: 'feature',
      target_branch: 'main',
      merged: false,
      opened_at: Time.current
    )
  end

  def test_valid_record
    assert_predicate @external_pull_request, :valid?
  end

  def test_requires_presence_of_core_attributes
    @external_pull_request.provider = nil
    @external_pull_request.external_repository = nil
    @external_pull_request.number = nil
    @external_pull_request.title = nil
    @external_pull_request.url = nil
    @external_pull_request.state = nil

    assert_not_predicate @external_pull_request, :valid?
    %i[provider external_repository number title url state].each do |attribute|
      assert @external_pull_request.errors[attribute].present?, "expected #{attribute} to be invalid"
    end
  end

  def test_enforces_uniqueness_of_number_per_provider_and_external_repository
    @external_pull_request.save!

    duplicate = @external_pull_request.dup
    assert_not_predicate duplicate, :valid?
    assert_includes duplicate.errors[:number], 'has already been taken'
  end

  def test_rejects_invalid_state
    @external_pull_request.state = 'merged'

    assert_not_predicate @external_pull_request, :valid?
    assert_includes @external_pull_request.errors[:state], 'is not included in the list'
  end

  def test_defaults_merged_to_false
    record = ExternalPullRequest.new(
      provider: 'github',
      external_repository: @external_repository,
      number: 2,
      title: 'Another feature',
      url: 'https://github.com/redmine/redmine_dev_integration/pull/2',
      state: 'open'
    )

    assert_predicate record, :valid?
    assert_equal false, record.merged
  end

  def test_links_multiple_issues_from_title_body_and_source_branch_without_duplicates
    project = Project.generate!(issue_key_prefix: 'AUTH')
    @external_repository.update!(redmine_project: project)
    issue_one = Issue.generate!(project: project, subject: 'One')
    issue_two = Issue.generate!(project: project, subject: 'Two')
    issue_three = Issue.generate!(project: project, subject: 'Three')

    @external_pull_request.title = "Fix #{issue_one.issue_key}"
    @external_pull_request.body = "Also addresses #{issue_two.issue_key}\nRevisits #{issue_one.issue_key}"
    @external_pull_request.source_branch = "feature/#{issue_three.issue_key}"
    @external_pull_request.save!

    result = @external_pull_request.link_issues_from_texts(@external_pull_request.title, @external_pull_request.body, @external_pull_request.source_branch)

    assert_equal [issue_one.issue_key, issue_two.issue_key, issue_three.issue_key], result.matched_keys
    assert_equal [issue_one.id, issue_two.id, issue_three.id], result.issue_ids
    assert_equal [issue_one.id, issue_two.id, issue_three.id], @external_pull_request.reload.issues.pluck(:id)

    assert_difference 'ExternalPullRequestIssue.count', 0 do
      @external_pull_request.link_issues_from_texts(@external_pull_request.title, @external_pull_request.body, @external_pull_request.source_branch, issue_one.issue_key)
    end
    assert_equal 3, @external_pull_request.external_pull_request_issues.count
  end

  def test_links_only_issues_from_mapped_project
    project = Project.generate!(issue_key_prefix: 'AUTH')
    other_project = Project.generate!(issue_key_prefix: 'OPS')
    @external_repository.update!(redmine_project: project)
    issue_one = Issue.generate!(project: project, subject: 'One')
    issue_two = Issue.generate!(project: other_project, subject: 'Two')

    @external_pull_request.title = "#{issue_one.issue_key} and #{issue_two.issue_key}"
    @external_pull_request.save!

    result = @external_pull_request.link_issues_from_texts(@external_pull_request.title)

    assert_equal [issue_one.issue_key, issue_two.issue_key], result.matched_keys
    assert_equal [issue_one.id, issue_two.id], result.issue_ids
    assert_equal [issue_one.id], @external_pull_request.reload.issues.pluck(:id)
    assert_equal [issue_one.id], @external_pull_request.external_pull_request_issues.pluck(:issue_id)
  end
end
