# frozen_string_literal: true

require_relative '../test_helper'

class IssueLinkerTest < ActiveSupport::TestCase
  def setup
    @linker = RedmineDevIntegration::IssueLinker.new
  end

  def test_resolves_one_valid_key_to_issue_id
    stub_issue_keys_where('AUTH-1' => 42)

    result = @linker.link('AUTH-1')

    assert_equal ['AUTH-1'], result.matched_keys
    assert_equal [42], result.issue_ids
  end

  def test_resolves_multiple_keys
    stub_issue_keys_where('AUTH-1' => 10, 'BUG-2' => 11)

    result = @linker.link('AUTH-1 and BUG-2')

    assert_equal %w[AUTH-1 BUG-2], result.matched_keys
    assert_equal [10, 11], result.issue_ids
  end

  def test_unresolved_key_remains_in_matched_keys_but_not_resolved_ids
    stub_issue_keys_where('AUTH-1' => 7)

    result = @linker.link('AUTH-1 BUG-2')

    assert_equal %w[AUTH-1 BUG-2], result.matched_keys
    assert_equal [7], result.issue_ids
  end

  def test_lowercase_key_resolves
    stub_issue_keys_where('AUTH-1' => 21)

    result = @linker.link('auth-1')

    assert_equal ['AUTH-1'], result.matched_keys
    assert_equal [21], result.issue_ids
  end

  def test_uses_extractor_instead_of_duplicating_regex
    extractor = mock('extractor')
    extractor.expects(:extract).with(['AUTH-1']).returns(['AUTH-1'])
    linker = RedmineDevIntegration::IssueLinker.new(extractor: extractor)

    result = linker.link(['AUTH-1'])

    assert_equal ['AUTH-1'], result.matched_keys
  end

  def test_without_find_by_issue_key_does_not_raise
    Issue.stubs(:respond_to?).with(:find_by_issue_key).returns(false)

    result = @linker.link('AUTH-1')

    assert_equal ['AUTH-1'], result.matched_keys
    assert_equal [], result.issue_ids
  end

  private

  def stub_issue_keys_where(mapping)
    pluck_data = mapping.map { |key, id| [key.upcase, id] }
    relation = mock
    relation.stubs(:pluck).with(:issue_key, :id).returns(pluck_data)
    Issue.stubs(:where).returns(relation)
  end
end
