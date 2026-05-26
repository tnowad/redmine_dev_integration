# frozen_string_literal: true

require_relative '../test_helper'

class ExternalBuildTest < ActiveSupport::TestCase
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

    @external_build = ExternalBuild.new(
      provider: 'github',
      external_repository: @external_repository,
      provider_build_id: '101',
      build_number: 42,
      name: 'CI build',
      status: 'queued',
      conclusion: nil,
      url: 'https://github.com/redmine/redmine_dev_integration/actions/runs/101',
      sha: 'abc123',
      ref: 'main',
      branch_name: 'main',
      author_login: 'contributor',
      started_at: Time.current,
      last_event_at: Time.current
    )
  end

  def test_valid_record
    assert_predicate @external_build, :valid?
  end

  def test_requires_presence_of_core_attributes
    @external_build.provider = nil
    @external_build.external_repository = nil
    @external_build.provider_build_id = nil
    @external_build.build_number = nil
    @external_build.name = nil
    @external_build.status = nil

    assert_not_predicate @external_build, :valid?
    %i[provider external_repository provider_build_id build_number name status].each do |attribute|
      assert @external_build.errors[attribute].present?, "expected #{attribute} to be invalid"
    end
  end

  def test_rejects_invalid_status
    @external_build.status = 'running'

    assert_not_predicate @external_build, :valid?
    assert_includes @external_build.errors[:status], 'is not included in the list'
  end

  def test_enforces_uniqueness_of_provider_build_id_per_provider_and_external_repository
    @external_build.save!

    duplicate = @external_build.dup
    assert_not_predicate duplicate, :valid?
    assert_includes duplicate.errors[:provider_build_id], 'has already been taken'
  end

  def test_links_issue_from_build_text_and_deduplicates
    project = Project.generate!(issue_key_prefix: 'AUTH')
    @external_repository.update!(redmine_project: project)
    issue = Issue.generate!(project: project, subject: 'Login fix')
    other_issue = Issue.generate!(project: project, subject: 'Docs fix')
    @external_build.save!

    result = @external_build.link_issues_from_texts("feature/#{issue.issue_key}-login", other_issue.issue_key, issue.issue_key)

    assert_equal [issue.issue_key, other_issue.issue_key], result.matched_keys
    assert_equal [issue.id, other_issue.id], result.issue_ids
    assert_equal [issue.id, other_issue.id], @external_build.reload.issues.pluck(:id)

    assert_difference 'ExternalBuildIssue.count', 0 do
      @external_build.link_issues_from_texts("#{issue.issue_key} #{other_issue.issue_key} #{issue.issue_key}")
    end
    assert_equal 2, @external_build.external_build_issues.count
  end

  def test_links_only_issues_from_mapped_project_and_ignores_unknown_keys
    project = Project.generate!(issue_key_prefix: 'AUTH')
    other_project = Project.generate!(issue_key_prefix: 'OPS')
    @external_repository.update!(redmine_project: project)
    issue = Issue.generate!(project: project, subject: 'Login fix')
    other_issue = Issue.generate!(project: other_project, subject: 'Other fix')
    @external_build.save!

    assert_nothing_raised do
      result = @external_build.link_issues_from_texts("#{issue.issue_key} #{other_issue.issue_key} AUTH-9999")
      assert_equal [issue.issue_key, other_issue.issue_key, 'AUTH-9999'], result.matched_keys
      assert_equal [issue.id, other_issue.id], result.issue_ids
    end

    assert_equal [issue.id], @external_build.reload.issues.pluck(:id)
    assert_equal [issue.id], @external_build.external_build_issues.pluck(:issue_id)
  end
end
