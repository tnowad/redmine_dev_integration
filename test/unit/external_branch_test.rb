# frozen_string_literal: true

require_relative '../test_helper'

class ExternalBranchTest < ActiveSupport::TestCase
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

    @external_branch = ExternalBranch.new(
      external_repository: @external_repository,
      name: 'main',
      url: 'https://github.com/redmine/redmine_dev_integration/tree/main',
      sha: 'abc123',
      state: 'active'
    )
  end

  def test_valid_record
    assert_predicate @external_branch, :valid?
  end

  def test_requires_presence_of_core_attributes
    @external_branch.external_repository = nil
    @external_branch.name = nil
    @external_branch.state = nil

    assert_not_predicate @external_branch, :valid?
    %i[external_repository name state].each do |attribute|
      assert @external_branch.errors[attribute].present?, "expected #{attribute} to be invalid"
    end
  end

  def test_rejects_invalid_state
    @external_branch.state = 'queued'

    assert_not_predicate @external_branch, :valid?
    assert_includes @external_branch.errors[:state], 'is not included in the list'
  end

  def test_enforces_uniqueness_of_name_per_external_repository
    @external_branch.save!

    duplicate = @external_branch.dup
    assert_not_predicate duplicate, :valid?
    assert_includes duplicate.errors[:name], 'has already been taken'
  end

  def test_soft_delete_marks_record_deleted
    @external_branch.save!

    assert_difference -> { ExternalBranch.where(state: 'deleted').count }, 1 do
      @external_branch.destroy
    end

    @external_branch.reload
    assert_predicate @external_branch, :deleted?
    assert_not_nil @external_branch.deleted_at
  end

  def test_soft_delete_helper_is_idempotent
    @external_branch.save!
    @external_branch.soft_delete!
    deleted_at = @external_branch.deleted_at

    assert_silent do
      @external_branch.soft_delete!
    end

    assert_equal deleted_at, @external_branch.deleted_at
  end

  def test_links_issues_from_branch_name_and_deduplicates
    project = Project.generate!(issue_key_prefix: 'AUTH')
    @external_repository.update!(redmine_project: project)
    @external_branch.save!
    issue_one = Issue.generate!(project: project, subject: 'One')
    issue_two = Issue.generate!(project: project, subject: 'Two')

    branch_name = "feature/#{issue_one.issue_key}-and-#{issue_two.issue_key}"
    result = @external_branch.link_issues_from_texts(branch_name, issue_one.issue_key)

    assert_equal [issue_one.issue_key, issue_two.issue_key], result.matched_keys
    assert_equal [issue_one.id, issue_two.id], result.issue_ids
    assert_equal [issue_one.id, issue_two.id], @external_branch.reload.issues.pluck(:id)

    assert_difference 'ExternalBranchIssue.count', 0 do
      @external_branch.link_issues_from_texts("#{issue_one.issue_key} #{issue_two.issue_key} #{issue_one.issue_key}")
    end
    assert_equal 2, @external_branch.external_branch_issues.count
  end

  def test_links_only_issues_from_mapped_project
    project = Project.generate!(issue_key_prefix: 'AUTH')
    other_project = Project.generate!(issue_key_prefix: 'OPS')
    @external_repository.update!(redmine_project: project)
    @external_branch.save!
    issue_one = Issue.generate!(project: project, subject: 'One')
    issue_two = Issue.generate!(project: other_project, subject: 'Two')

    result = @external_branch.link_issues_from_texts("#{issue_one.issue_key} #{issue_two.issue_key}")

    assert_equal [issue_one.issue_key, issue_two.issue_key], result.matched_keys
    assert_equal [issue_one.id, issue_two.id], result.issue_ids
    assert_equal [issue_one.id], @external_branch.reload.issues.pluck(:id)
    assert_equal [issue_one.id], @external_branch.external_branch_issues.pluck(:issue_id)
  end
end
