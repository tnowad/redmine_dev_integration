# frozen_string_literal: true

require_relative '../test_helper'

class IssueLinkerTest < ActiveSupport::TestCase
  def setup
    @linker = RedmineDevIntegration::IssueLinker.new
  end

  def test_resolves_one_valid_key_to_issue_id
    issue = mock('issue')
    issue.stubs(:id).returns(42)
    Issue.stubs(:find_by_issue_key).with('AUTH-1').returns(issue)

    result = @linker.link('AUTH-1')

    assert_equal ['AUTH-1'], result.matched_keys
    assert_equal [42], result.issue_ids
  end

  def test_resolves_multiple_keys
    first_issue = mock('first_issue')
    first_issue.stubs(:id).returns(10)
    second_issue = mock('second_issue')
    second_issue.stubs(:id).returns(11)

    Issue.stubs(:find_by_issue_key).with('AUTH-1').returns(first_issue)
    Issue.stubs(:find_by_issue_key).with('BUG-2').returns(second_issue)

    result = @linker.link('AUTH-1 and BUG-2')

    assert_equal %w[AUTH-1 BUG-2], result.matched_keys
    assert_equal [10, 11], result.issue_ids
  end

  def test_unresolved_key_remains_in_matched_keys_but_not_resolved_ids
    issue = mock('issue')
    issue.stubs(:id).returns(7)
    Issue.stubs(:find_by_issue_key).with('AUTH-1').returns(issue)
    Issue.stubs(:find_by_issue_key).with('BUG-2').returns(nil)

    result = @linker.link('AUTH-1 BUG-2')

    assert_equal %w[AUTH-1 BUG-2], result.matched_keys
    assert_equal [7], result.issue_ids
  end

  def test_lowercase_key_resolves
    issue = mock('issue')
    issue.stubs(:id).returns(21)
    Issue.stubs(:find_by_issue_key).with('AUTH-1').returns(issue)

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
end
