# frozen_string_literal: true

require_relative '../test_helper'

class PushCommitTextExtractorTest < ActiveSupport::TestCase
  def test_extracts_messages_from_github_style_commits
    commits = [
      { 'message' => 'Fix login bug' },
      { 'message' => 'Add feature toggle' }
    ]

    assert_equal ['Fix login bug', 'Add feature toggle'],
                 RedmineDevIntegration::PushCommitTextExtractor.extract(commits)
  end

  def test_extracts_messages_from_gitlab_style_commits
    commits = [
      { 'id' => 'abc123', 'message' => 'Fix AUTH-42' },
      { 'id' => 'def456', 'message' => 'Update docs' }
    ]

    assert_equal ['Fix AUTH-42', 'Update docs'],
                 RedmineDevIntegration::PushCommitTextExtractor.extract(commits)
  end

  def test_extracts_messages_from_bitbucket_style_commits
    commits = [
      { 'hash' => 'abc123', 'message' => 'Fix AUTH-42' },
      { 'hash' => 'def456', 'message' => 'Refactor' }
    ]

    assert_equal ['Fix AUTH-42', 'Refactor'],
                 RedmineDevIntegration::PushCommitTextExtractor.extract(commits)
  end

  def test_returns_empty_array_for_nil
    assert_equal [], RedmineDevIntegration::PushCommitTextExtractor.extract(nil)
  end

  def test_returns_empty_array_for_non_array
    assert_equal [], RedmineDevIntegration::PushCommitTextExtractor.extract('invalid')
    assert_equal [], RedmineDevIntegration::PushCommitTextExtractor.extract({})
  end

  def test_returns_empty_array_for_empty_array
    assert_equal [], RedmineDevIntegration::PushCommitTextExtractor.extract([])
  end

  def test_skips_entries_without_message_key
    commits = [
      { 'message' => 'Fix AUTH-42' },
      { 'id' => 'abc123' },
      { 'message' => 'Update docs' }
    ]

    assert_equal ['Fix AUTH-42', 'Update docs'],
                 RedmineDevIntegration::PushCommitTextExtractor.extract(commits)
  end

  def test_skips_non_hash_entries
    commits = [
      { 'message' => 'Fix AUTH-42' },
      'not a hash',
      { 'message' => 'Update docs' },
      nil
    ]

    assert_equal ['Fix AUTH-42', 'Update docs'],
                 RedmineDevIntegration::PushCommitTextExtractor.extract(commits)
  end
end
