# frozen_string_literal: true

require_relative '../test_helper'

class ProviderRepositoryValidatorTest < ActiveSupport::TestCase
  fixtures :projects, :repositories

  def setup
    @project = projects(:projects_001)
    @base_attributes = {
      provider: 'github',
      provider_repository_id: '123',
      owner: 'redmine',
      repo_name: 'redmine_dev_integration',
      full_name: 'redmine/redmine_dev_integration',
      url: 'https://github.com/redmine/redmine_dev_integration',
      redmine_repository_id: repositories(:repositories_001).id
    }
  end

  def test_accepts_valid_attributes_when_provider_enabled
    result = validate_with_settings({'github_provider_enabled' => '1'})

    assert_predicate result, :valid?
    assert_equal 'github', result.normalized_attributes[:provider]
    assert_equal '123', result.normalized_attributes[:provider_repository_id]
  end

  def test_rejects_github_when_disabled
    result = validate_with_settings({'github_provider_enabled' => '0'})

    assert_not_predicate result, :valid?
    assert_includes result.errors[:provider], 'provider is disabled'
  end

  def test_rejects_gitlab_when_disabled
    result = validate_with_settings({'gitlab_provider_enabled' => false}, provider: 'gitlab', provider_repository_id: '456', url: 'https://gitlab.example.com/redmine/redmine_dev_integration')

    assert_not_predicate result, :valid?
    assert_includes result.errors[:provider], 'provider is disabled'
  end

  def test_rejects_invalid_provider
    result = validate_with_settings({'github_provider_enabled' => '1'}, provider: 'unsupported')

    assert_not_predicate result, :valid?
    assert_includes result.errors[:provider], 'provider is invalid'
  end

  def test_rejects_non_uuid_provider_repository_id_for_bitbucket
    result = validate_with_settings(
      {'bitbucket_provider_enabled' => '1'},
      provider: 'bitbucket',
      provider_repository_id: 'not-a-uuid',
      owner: 'workspace',
      repo_name: 'repo',
      full_name: 'workspace/repo',
      url: 'https://bitbucket.org/workspace/repo'
    )

    assert_not_predicate result, :valid?
    assert_includes result.errors[:provider_repository_id], 'Bitbucket provider repository ID must be a valid UUID'
  end

  def test_accepts_valid_uuid_provider_repository_id_for_bitbucket
    result = validate_with_settings(
      {'bitbucket_provider_enabled' => '1'},
      provider: 'bitbucket',
      provider_repository_id: 'abc123de-f456-7890-1234-567890abcdef',
      owner: 'workspace',
      repo_name: 'repo',
      full_name: 'workspace/repo',
      url: 'https://bitbucket.org/workspace/repo'
    )

    assert_predicate result, :valid?
  end

  def test_accepts_valid_uuid_with_braces_for_bitbucket
    result = validate_with_settings(
      {'bitbucket_provider_enabled' => '1'},
      provider: 'bitbucket',
      provider_repository_id: '{abc123de-f456-7890-1234-567890abcdef}',
      owner: 'workspace',
      repo_name: 'repo',
      full_name: 'workspace/repo',
      url: 'https://bitbucket.org/workspace/repo'
    )

    assert_predicate result, :valid?
  end

  def test_rejects_disabled_bitbucket
    result = validate_with_settings(
      {'bitbucket_provider_enabled' => '0'},
      provider: 'bitbucket',
      provider_repository_id: 'abc123de-f456-7890-1234-567890abcdef',
      owner: 'workspace',
      repo_name: 'repo',
      full_name: 'workspace/repo',
      url: 'https://bitbucket.org/workspace/repo'
    )

    assert_not_predicate result, :valid?
    assert_includes result.errors[:provider], 'provider is disabled'
  end

  def test_rejects_duplicate_provider_repository_id_for_same_provider
    ExternalRepository.create!(
      @base_attributes.merge(redmine_project: @project, provider: 'github')
    )

    result = validate_with_settings({'github_provider_enabled' => '1'})

    assert_not_predicate result, :valid?
    assert_includes result.errors[:provider_repository_id], 'repository already connected'
  end

  def test_allows_existing_repository_to_keep_same_provider_repository_id_on_update
    existing_repository = ExternalRepository.create!(
      @base_attributes.merge(redmine_project: @project, provider: 'github')
    )

    result = validate_with_settings({'github_provider_enabled' => '1'}, existing_repository: existing_repository)

    assert_predicate result, :valid?
  end

  def test_rejects_provider_repository_id_that_looks_like_full_name
    result = validate_with_settings({'github_provider_enabled' => '1'}, provider_repository_id: 'redmine/redmine_dev_integration')

    assert_not_predicate result, :valid?
    assert_includes result.errors[:provider_repository_id], 'Github provider repository ID must be numeric'
  end

  def test_rejects_non_numeric_provider_repository_id_for_github
    result = validate_with_settings({'github_provider_enabled' => '1'}, provider_repository_id: 'redmine-dev-integration')

    assert_not_predicate result, :valid?
    assert_includes result.errors[:provider_repository_id], 'Github provider repository ID must be numeric'
  end

  def test_rejects_invalid_url
    result = validate_with_settings({'github_provider_enabled' => '1'}, url: 'ftp://github.com/redmine/redmine_dev_integration')

    assert_not_predicate result, :valid?
    assert_includes result.errors[:url], 'URL must be HTTP or HTTPS'
  end

  def test_derives_repository_metadata_from_quick_connect_input
    result = validate_with_settings(
      {'github_provider_enabled' => '1'},
      owner: nil,
      repo_name: nil,
      full_name: nil,
      url: nil,
      repository_url_or_path: 'https://github.com/redmine/redmine_dev_integration'
    )

    assert_predicate result, :valid?
    assert_equal 'redmine', result.normalized_attributes[:owner]
    assert_equal 'redmine_dev_integration', result.normalized_attributes[:repo_name]
    assert_equal 'redmine/redmine_dev_integration', result.normalized_attributes[:full_name]
    assert_equal 'https://github.com/redmine/redmine_dev_integration', result.normalized_attributes[:url]
    assert_not result.normalized_attributes.key?(:repository_url_or_path)
  end

  def test_keeps_manual_repository_metadata_when_quick_connect_input_is_unparseable
    result = validate_with_settings(
      {'github_provider_enabled' => '1'},
      repository_url_or_path: 'https://example.com/redmine/redmine_dev_integration'
    )

    assert_predicate result, :valid?
    assert_equal 'redmine', result.normalized_attributes[:owner]
    assert_equal 'redmine_dev_integration', result.normalized_attributes[:repo_name]
    assert_equal 'redmine/redmine_dev_integration', result.normalized_attributes[:full_name]
    assert_equal 'https://github.com/redmine/redmine_dev_integration', result.normalized_attributes[:url]
  end

  def test_rejects_redmine_repository_from_another_project
    result = validate_with_settings({'github_provider_enabled' => '1'}, redmine_repository_id: repositories(:repositories_002).id)

    assert_not_predicate result, :valid?
    assert_includes result.errors[:redmine_repository_id], 'SCM repository must belong to this project'
  end

  def test_rejects_missing_owner_repo_name_and_full_name
    result = validate_with_settings({'github_provider_enabled' => '1'}, owner: nil, repo_name: '', full_name: ' ')

    assert_not_predicate result, :valid?
    assert_includes result.errors[:owner], 'owner is required'
    assert_includes result.errors[:repo_name], 'repo name is required'
    assert_includes result.errors[:full_name], 'full name is required'
  end

  private

  def validate_with_settings(settings, overrides = {})
    Setting.stubs(:plugin_redmine_dev_integration).returns(settings)

    RedmineDevIntegration::ProviderRepositoryValidator.call(
      project: @project,
      attributes: @base_attributes.merge(overrides),
      existing_repository: overrides.fetch(:existing_repository, nil)
    )
  end
end
