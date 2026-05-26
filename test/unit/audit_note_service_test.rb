# frozen_string_literal: true

require_relative '../test_helper'

class AuditNoteServiceTest < ActiveSupport::TestCase
  def setup
    @service = RedmineDevIntegration::AuditNoteService.new
    @issue = Issue.find(1)
    @user = User.find(1)
    @base_note = 'Synced from external system'
    @marker = 'github:pr:7'
    @duplicate_marker = 'github:pr:8'
    User.current = @user
  end

  def test_first_note_creates_journal
    assert_difference 'Journal.count', 1 do
      result = @service.call(issue: @issue, note: @base_note, marker: @marker, provider_url: 'https://github.com/redmine/redmine_dev_integration/pull/7', external_object_id: '7', user: @user)
      assert_predicate result, :created?
    end

    journal = @issue.journals.order(:id).last
    assert_includes journal.notes, @base_note
    assert_includes journal.notes, '[redmine-dev-integration:github:pr:7]'
    assert_includes journal.notes, 'provider_url=https://github.com/redmine/redmine_dev_integration/pull/7'
    assert_includes journal.notes, 'external_object_id=7'
  end

  def test_same_marker_skips_duplicate
    @service.call(issue: @issue, note: @base_note, marker: @duplicate_marker, user: @user)

    assert_no_difference 'Journal.count' do
      result = @service.call(issue: @issue, note: 'Another note', marker: @duplicate_marker, user: @user)
      assert_predicate result, :skipped?
    end
  end

  def test_different_marker_creates_second_note
    assert_difference 'Journal.count', 2 do
      @service.call(issue: @issue, note: @base_note, marker: @marker, user: @user)
      result = @service.call(issue: @issue, note: 'Second sync note', marker: 'github:pr:9', user: @user)
      assert_predicate result, :created?
    end
  end

  def test_blank_note_skips
    assert_no_difference 'Journal.count' do
      result = @service.call(issue: @issue, note: '   ', marker: @marker, user: @user)
      assert_predicate result, :skipped?
    end
  end
end
