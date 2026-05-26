# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../../lib/redmine_dev_integration/provider_repository_parser'

class ProviderRepositoryParserTest < ActiveSupport::TestCase
  def test_parses_github_https_url
    result = parse('github', 'https://github.com/owner/repo')

    assert_equal 'github', result.provider
    assert_equal 'owner', result.owner
    assert_equal 'repo', result.repo_name
    assert_equal 'owner/repo', result.full_name
    assert_equal 'https://github.com/owner/repo', result.url
  end

  def test_parses_github_http_git_url
    result = parse('github', 'http://github.com/owner/repo.git')

    assert_equal 'owner', result.owner
    assert_equal 'repo', result.repo_name
    assert_equal 'owner/repo', result.full_name
    assert_equal 'https://github.com/owner/repo', result.url
  end

  def test_parses_github_ssh_url
    result = parse('github', 'git@github.com:owner/repo.git')

    assert_equal 'owner', result.owner
    assert_equal 'repo', result.repo_name
    assert_equal 'owner/repo', result.full_name
    assert_equal 'https://github.com/owner/repo', result.url
  end

  def test_parses_github_shorthand
    result = parse('github', 'owner/repo')

    assert_equal 'owner', result.owner
    assert_equal 'repo', result.repo_name
    assert_equal 'owner/repo', result.full_name
    assert_equal 'https://github.com/owner/repo', result.url
  end

  def test_parses_gitlab_https_url_with_nested_namespace
    result = parse('gitlab', 'https://gitlab.com/group/subgroup/repo')

    assert_equal 'group/subgroup', result.owner
    assert_equal 'repo', result.repo_name
    assert_equal 'group/subgroup/repo', result.full_name
    assert_equal 'https://gitlab.com/group/subgroup/repo', result.url
  end

  def test_parses_gitlab_ssh_url_with_nested_namespace
    result = parse('gitlab', 'git@gitlab.com:group/subgroup/repo.git')

    assert_equal 'group/subgroup', result.owner
    assert_equal 'repo', result.repo_name
    assert_equal 'group/subgroup/repo', result.full_name
    assert_equal 'https://gitlab.com/group/subgroup/repo', result.url
  end

  def test_parses_gitlab_shorthand
    result = parse('gitlab', 'group/subgroup/repo')

    assert_equal 'group/subgroup', result.owner
    assert_equal 'repo', result.repo_name
    assert_equal 'group/subgroup/repo', result.full_name
    assert_equal 'https://gitlab.com/group/subgroup/repo', result.url
  end

  def test_rejects_blank_input
    assert_nil parse('github', ' ')
    assert_nil parse('gitlab', nil)
  end

  def test_rejects_unparseable_input
    assert_nil parse('github', 'https://example.com/owner/repo')
    assert_nil parse('github', 'owner')
    assert_nil parse('gitlab', 'group')
  end

  private

  def parse(provider, repository)
    RedmineDevIntegration::ProviderRepositoryParser.call(provider: provider, repository: repository)
  end
end
