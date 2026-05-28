# frozen_string_literal: true

require_relative '../test_helper'

class ExternalReleaseTest < ActiveSupport::TestCase
  fixtures :projects, :repositories

  def setup
    @external_repository = ExternalRepository.create!(
      provider: 'github',
      provider_repository_id: '123',
      owner: 'redmine',
      repo_name: 'redmine_dev_integration',
      full_name: 'redmine/redmine_dev_integration',
      url: 'https://github.com/redmine/redmine_dev_integration',
      redmine_project: projects(:projects_001)
    )

    @external_release = ExternalRelease.new(
      provider: 'github',
      external_repository: @external_repository,
      name: 'v1.0.0',
      tag_name: 'v1.0.0',
      status: 'published',
      body: 'Release notes for v1.0.0',
      url: 'https://github.com/redmine/redmine_dev_integration/releases/tag/v1.0.0',
      author_login: 'contributor',
      released_at: Time.current
    )
  end

  def test_valid_record
    assert_predicate @external_release, :valid?
  end

  def test_requires_presence_of_core_attributes
    @external_release.provider = nil
    @external_release.external_repository = nil
    @external_release.name = nil
    @external_release.status = nil

    assert_not_predicate @external_release, :valid?
    %i[provider external_repository name status].each do |attribute|
      assert @external_release.errors[attribute].present?, "expected #{attribute} to be invalid"
    end
  end

  def test_enforces_uniqueness_of_name_per_provider_and_repository
    @external_release.save!

    duplicate = @external_release.dup
    assert_not_predicate duplicate, :valid?
    assert_includes duplicate.errors[:name], 'has already been taken'
  end

  def test_allows_same_name_different_provider
    @external_release.save!

    other_repo = ExternalRepository.create!(
      provider: 'gitlab',
      provider_repository_id: '456',
      owner: 'redmine',
      repo_name: 'other_repo',
      full_name: 'redmine/other_repo',
      url: 'https://gitlab.com/redmine/other_repo',
      redmine_project: projects(:projects_001)
    )

    different_provider = ExternalRelease.new(
      provider: 'gitlab',
      external_repository: other_repo,
      name: 'v1.0.0',
      tag_name: 'v1.0.0',
      status: 'published'
    )
    assert_predicate different_provider, :valid?
  end

  def test_published_scope_excludes_drafts
    published = @external_release
    published.save!

    draft = ExternalRelease.create!(
      provider: 'github',
      external_repository: @external_repository,
      name: 'v2.0.0-draft',
      tag_name: 'v2.0.0',
      status: 'draft'
    )

    published_releases = ExternalRelease.published
    assert_includes published_releases, published
    assert_not_includes published_releases, draft
  end

  def test_belongs_to_external_repository
    @external_release.save!
    assert_equal @external_repository, @external_release.external_repository
  end

  def test_belongs_to_redmine_version_optional
    @external_release.save!
    assert_nil @external_release.redmine_version
  end

  def test_link_issues_from_deployments
    project = Project.generate!(issue_key_prefix: 'REL')
    @external_repository.update!(redmine_project: project)
    issue = Issue.generate!(project: project, subject: 'Release issue')
    @external_release.save!

    deployment = ExternalDeployment.create!(
      provider: 'github',
      external_repository: @external_repository,
      external_release: @external_release,
      provider_deployment_id: 'deploy-1',
      environment_name: 'production',
      status: 'success',
      sha: 'abc123',
      ref: 'refs/tags/v1.0.0',
      branch_name: 'refs/tags/v1.0.0'
    )
    ExternalDeploymentIssue.create!(external_deployment: deployment, issue: issue)

    @external_release.link_issues_from_deployments
    assert_equal [issue.id], @external_release.reload.issues.pluck(:id)
    assert_equal 1, @external_release.external_release_issues.count
  end

  def test_link_issues_deduplicates
    project = Project.generate!(issue_key_prefix: 'REL')
    @external_repository.update!(redmine_project: project)
    issue = Issue.generate!(project: project, subject: 'Release issue')
    @external_release.save!

    deployment1 = ExternalDeployment.create!(
      provider: 'github',
      external_repository: @external_repository,
      external_release: @external_release,
      provider_deployment_id: 'deploy-1',
      environment_name: 'staging',
      status: 'success',
      sha: 'abc123',
      ref: 'refs/tags/v1.0.0',
      branch_name: 'refs/tags/v1.0.0'
    )
    ExternalDeploymentIssue.create!(external_deployment: deployment1, issue: issue)

    deployment2 = ExternalDeployment.create!(
      provider: 'github',
      external_repository: @external_repository,
      external_release: @external_release,
      provider_deployment_id: 'deploy-2',
      environment_name: 'production',
      status: 'success',
      sha: 'def456',
      ref: 'refs/tags/v1.0.0',
      branch_name: 'refs/tags/v1.0.0'
    )
    ExternalDeploymentIssue.create!(external_deployment: deployment2, issue: issue)

    @external_release.link_issues_from_deployments

    assert_difference 'ExternalReleaseIssue.count', 0 do
      @external_release.link_issues_from_deployments
    end
    assert_equal 1, @external_release.external_release_issues.count
    assert_equal [issue.id], @external_release.issues.pluck(:id)
  end
end
