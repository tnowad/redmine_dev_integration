# frozen_string_literal: true

require_relative '../test_helper'

class ExternalRepositoryTest < ActiveSupport::TestCase
  fixtures :projects, :repositories

  def setup
    @external_repository = build_repository
  end

  def test_valid_github_repository
    assert_predicate @external_repository, :valid?
  end

  def test_valid_gitlab_repository_with_nested_group_path
    repository = build_repository(
      provider: 'gitlab',
      provider_repository_id: '456',
      owner: 'redmine/subgroup',
      full_name: 'redmine/subgroup/redmine_dev_integration',
      url: 'https://gitlab.example.com/redmine/subgroup/redmine_dev_integration'
    )

    assert_predicate repository, :valid?
  end

  def test_invalid_provider_fails
    @external_repository.provider = 'bogus'

    assert_not_predicate @external_repository, :valid?
    assert_includes @external_repository.errors[:provider], 'is not included in the list'
  end

  def test_enforces_uniqueness_of_provider_and_provider_repository_id
    @external_repository.save!

    duplicate = @external_repository.dup
    assert_not_predicate duplicate, :valid?
    assert_includes duplicate.errors[:provider_repository_id], 'has already been taken'
  end

  def test_allows_same_provider_repository_id_on_different_provider
    @external_repository.save!

    duplicate = build_repository(
      provider: 'gitlab',
      provider_repository_id: '123',
      owner: 'redmine/subgroup',
      full_name: 'redmine/subgroup/redmine_dev_integration',
      url: 'https://gitlab.example.com/redmine/subgroup/redmine_dev_integration'
    )

    assert_predicate duplicate, :valid?
  end

  def test_redmine_repository_from_another_project_fails
    @external_repository.redmine_repository = repositories(:repositories_002)

    assert_not_predicate @external_repository, :valid?
    assert_includes @external_repository.errors[:redmine_repository_id], 'must belong to the same Redmine project'
  end

  def test_allows_missing_repository_association
    @external_repository.redmine_repository = nil
    assert_predicate @external_repository, :valid?
  end

  def test_rejects_non_http_url
    @external_repository.url = 'ftp://github.com/redmine/redmine_dev_integration'

    assert_not_predicate @external_repository, :valid?
    assert_includes @external_repository.errors[:url], 'is invalid'
  end

  def test_rejects_full_name_without_slash
    @external_repository.full_name = 'redmine_dev_integration'

    assert_not_predicate @external_repository, :valid?
    assert_includes @external_repository.errors[:full_name], 'is invalid'
  end

  def test_allows_inactive_repository
    @external_repository.active = false

    assert_predicate @external_repository, :valid?
  end

  def test_branch_url_github
    repo = ExternalRepository.new(provider: 'github', url: 'https://github.com/owner/repo')
    assert_equal 'https://github.com/owner/repo/tree/feature/test', repo.branch_url('feature/test')
  end

  def test_branch_url_gitlab
    repo = ExternalRepository.new(provider: 'gitlab', url: 'https://gitlab.example.com/group/repo')
    assert_equal 'https://gitlab.example.com/group/repo/-/tree/fix/bug-42', repo.branch_url('fix/bug-42')
  end

  def test_branch_url_bitbucket
    repo = ExternalRepository.new(provider: 'bitbucket', url: 'https://bitbucket.org/team/repo')
    assert_equal 'https://bitbucket.org/team/repo/src/hotfix/crash', repo.branch_url('hotfix/crash')
  end

  private

  def build_repository(attributes = {})
    ExternalRepository.new(
      {
        provider: 'github',
        provider_repository_id: '123',
        owner: 'redmine',
        repo_name: 'redmine_dev_integration',
        full_name: 'redmine/redmine_dev_integration',
        url: 'https://github.com/redmine/redmine_dev_integration',
        redmine_project: projects(:projects_001),
        redmine_repository: repositories(:repositories_001),
        active: true
      }.merge(attributes)
    )
  end
end
