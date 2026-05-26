# frozen_string_literal: true

require_relative '../test_helper'

class IssueKeyExtractorTest < ActiveSupport::TestCase
  def setup
    @extractor = RedmineDevIntegration::IssueKeyExtractor.new
  end

  def test_extracts_uppercase_key
    assert_equal ['AUTH-1'], @extractor.extract('AUTH-1')
  end

  def test_extracts_lowercase_key_and_normalizes
    assert_equal ['AUTH-1'], @extractor.extract('auth-1')
  end

  def test_extracts_key_from_branch_name
    assert_equal ['AUTH-1'], @extractor.extract('feature/AUTH-1-login')
  end

  def test_extracts_multiple_keys
    assert_equal %w[AUTH-1 BUG-2], @extractor.extract('AUTH-1 and BUG-2')
  end

  def test_dedupes_duplicate_keys
    assert_equal ['AUTH-1'], @extractor.extract('AUTH-1 auth-1 AUTH-1')
  end

  def test_rejects_invalid_short_prefix
    assert_equal [], @extractor.extract('A-1')
  end

  def test_rejects_invalid_prefix_starting_with_digit
    assert_equal [], @extractor.extract('1AUTH-1')
  end
end
