# frozen_string_literal: true

require_relative '../test_helper'

class ExternalDeploymentTest < ActiveSupport::TestCase
  fixtures :projects, :repositories

  def setup
    @external_repository = ExternalRepository.new(
      provider: 'gitlab',
      provider_repository_id: '123',
      owner: 'redmine',
      repo_name: 'redmine_dev_integration',
      full_name: 'redmine/redmine_dev_integration',
      url: 'https://gitlab.com/redmine/redmine_dev_integration',
      redmine_project: projects(:projects_001)
    )
    @external_repository.save!

    @external_deployment = ExternalDeployment.new(
      provider: 'gitlab',
      external_repository: @external_repository,
      provider_deployment_id: '9001',
      environment_name: 'staging',
      environment_url: 'https://staging.example.test',
      status: 'pending',
      sha: 'abc123',
      ref: 'main',
      branch_name: 'main',
      description: 'Deploy to staging',
      creator_login: 'contributor',
      started_at: Time.current,
      last_event_at: Time.current
    )
  end

  def test_valid_record
    assert_predicate @external_deployment, :valid?
  end

  def test_requires_presence_of_core_attributes
    @external_deployment.provider = nil
    @external_deployment.external_repository = nil
    @external_deployment.provider_deployment_id = nil
    @external_deployment.environment_name = nil
    @external_deployment.status = nil

    assert_not_predicate @external_deployment, :valid?
    %i[provider external_repository provider_deployment_id environment_name status].each do |attribute|
      assert @external_deployment.errors[attribute].present?, "expected #{attribute} to be invalid"
    end
  end

  def test_rejects_invalid_status
    @external_deployment.status = 'running'

    assert_not_predicate @external_deployment, :valid?
    assert_includes @external_deployment.errors[:status], 'is not included in the list'
  end

  def test_enforces_uniqueness_of_provider_deployment_id_per_provider_repository_and_environment
    @external_deployment.save!

    duplicate = @external_deployment.dup
    assert_not_predicate duplicate, :valid?
    assert_includes duplicate.errors[:provider_deployment_id], 'has already been taken'
  end

  def test_links_issue_from_deployment_text_and_deduplicates
    project = Project.generate!(issue_key_prefix: 'AUTH')
    @external_repository.update!(redmine_project: project)
    issue = Issue.generate!(project: project, subject: 'Deploy target')
    other_issue = Issue.generate!(project: project, subject: 'Second target')
    @external_deployment.save!

    result = @external_deployment.link_issues_from_texts("Deploy #{issue.issue_key} to staging", other_issue.issue_key, issue.issue_key)

    assert_equal [issue.issue_key, other_issue.issue_key], result.matched_keys
    assert_equal [issue.id, other_issue.id], result.issue_ids
    assert_equal [issue.id, other_issue.id], @external_deployment.reload.issues.pluck(:id)

    assert_difference 'ExternalDeploymentIssue.count', 0 do
      @external_deployment.link_issues_from_texts("#{issue.issue_key} #{other_issue.issue_key} #{issue.issue_key}")
    end
    assert_equal 2, @external_deployment.external_deployment_issues.count
  end

  def test_links_only_issues_from_mapped_project_and_ignores_unknown_keys
    project = Project.generate!(issue_key_prefix: 'AUTH')
    other_project = Project.generate!(issue_key_prefix: 'OPS')
    @external_repository.update!(redmine_project: project)
    issue = Issue.generate!(project: project, subject: 'Deploy target')
    other_issue = Issue.generate!(project: other_project, subject: 'Other target')
    @external_deployment.save!

    assert_nothing_raised do
      result = @external_deployment.link_issues_from_texts("#{issue.issue_key} #{other_issue.issue_key} AUTH-9999")
      assert_equal [issue.issue_key, other_issue.issue_key, 'AUTH-9999'], result.matched_keys
      assert_equal [issue.id, other_issue.id], result.issue_ids
    end

    assert_equal [issue.id], @external_deployment.reload.issues.pluck(:id)
    assert_equal [issue.id], @external_deployment.external_deployment_issues.pluck(:issue_id)
  end
end
