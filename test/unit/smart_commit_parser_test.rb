# frozen_string_literal: true

require_relative '../test_helper'
require 'strscan'

class SmartCommitParserTest < ActiveSupport::TestCase
  def setup
    @parser = RedmineDevIntegration::SmartCommitParser.new
  end

  def test_returns_empty_array_for_blank_text
    assert_equal [], @parser.parse(nil)
    assert_equal [], @parser.parse('')
    assert_equal [], @parser.parse('   ')
  end

  def test_parses_comment_command
    commands = @parser.parse('RAK-1 #comment Fixed the bug')
    assert_equal 1, commands.size
    assert_equal 'RAK-1', commands[0].issue_key
    assert_equal :comment, commands[0].action
    assert_equal 'Fixed the bug', commands[0].value
  end

  def test_parses_done_command
    commands = @parser.parse('RAK-1 #done')
    assert_equal 1, commands.size
    assert_equal 'RAK-1', commands[0].issue_key
    assert_equal :done, commands[0].action
    assert_nil commands[0].value
  end

  def test_parses_time_command
    commands = @parser.parse('RAK-1 #time 1h')
    assert_equal 1, commands.size
    assert_equal 'RAK-1', commands[0].issue_key
    assert_equal :time, commands[0].action
    assert_equal '1h', commands[0].value
  end

  def test_parses_time_with_minutes
    commands = @parser.parse('RAK-1 #time 30m')
    assert_equal 1, commands.size
    assert_equal :time, commands[0].action
    assert_equal '30m', commands[0].value
  end

  def test_parses_time_with_hours_and_minutes
    commands = @parser.parse('RAK-1 #time 1h 30m')
    assert_equal 1, commands.size
    assert_equal :time, commands[0].action
    assert_equal '1h 30m', commands[0].value
  end

  def test_parses_assign_command
    commands = @parser.parse('RAK-1 #assign jdoe')
    assert_equal 1, commands.size
    assert_equal 'RAK-1', commands[0].issue_key
    assert_equal :assign, commands[0].action
    assert_equal 'jdoe', commands[0].value
  end

  def test_parses_multiple_issue_keys
    commands = @parser.parse('RAK-1 #done RAK-2 #comment Another fix')
    assert_equal 2, commands.size

    assert_equal 'RAK-1', commands[0].issue_key
    assert_equal :done, commands[0].action

    assert_equal 'RAK-2', commands[1].issue_key
    assert_equal :comment, commands[1].action
    assert_equal 'Another fix', commands[1].value
  end

  def test_parses_multiple_commands_for_same_issue_key
    commands = @parser.parse('RAK-1 #comment Fixed #done #time 1h')
    assert_equal 3, commands.size

    assert_equal :comment, commands[0].action
    assert_equal 'Fixed', commands[0].value
    assert_equal :done, commands[1].action
    assert_equal :time, commands[2].action
    assert_equal '1h', commands[2].value
  end

  def test_ignores_commands_without_issue_key
    commands = @parser.parse('#comment No issue key #done')
    assert_equal 0, commands.size
  end

  def test_handles_lowercase_issue_key
    commands = @parser.parse('rak-1 #done')
    assert_equal 1, commands.size
    assert_equal 'RAK-1', commands[0].issue_key
  end

  def test_handles_issue_key_in_middle_of_text
    commands = @parser.parse('Some text RAK-1 #done more text')
    assert_equal 1, commands.size
    assert_equal 'RAK-1', commands[0].issue_key
    assert_equal :done, commands[0].action
  end

  def test_parses_case_insensitive_commands
    commands = @parser.parse('RAK-1 #Comment text #DONE #Time 2h #ASSIGN jdoe')
    assert_equal 4, commands.size
    assert_equal :comment, commands[0].action
    assert_equal :done, commands[1].action
    assert_equal :time, commands[2].action
    assert_equal :assign, commands[3].action
  end

  def test_comment_stops_at_next_command
    commands = @parser.parse('RAK-1 #comment Fix the thing #done')
    assert_equal 2, commands.size
    assert_equal :comment, commands[0].action
    assert_equal 'Fix the thing', commands[0].value
    assert_equal :done, commands[1].action
  end

  def test_comment_stops_at_next_issue_key
    commands = @parser.parse('RAK-1 #comment Fixed bug RAK-2 #done')
    assert_equal 2, commands.size
    assert_equal :comment, commands[0].action
    assert_equal 'Fixed bug', commands[0].value
    assert_equal 'RAK-2', commands[1].issue_key
  end

  def test_comment_with_multiple_words
    commands = @parser.parse('RAK-1 #comment This is a long comment text')
    assert_equal 1, commands.size
    assert_equal :comment, commands[0].action
    assert_equal 'This is a long comment text', commands[0].value
  end

  def test_empty_comment_value
    commands = @parser.parse('RAK-1 #comment')
    assert_equal 1, commands.size
    assert_equal :comment, commands[0].action
    assert_nil commands[0].value
  end

  def test_empty_time_value
    commands = @parser.parse('RAK-1 #time')
    assert_equal 1, commands.size
    assert_equal :time, commands[0].action
    assert_nil commands[0].value
  end

  def test_empty_assign_value
    commands = @parser.parse('RAK-1 #assign')
    assert_equal 1, commands.size
    assert_equal :assign, commands[0].action
    assert_nil commands[0].value
  end

  def test_multiple_issue_keys_with_multiple_commands
    text = "RAK-1 #done #time 2h\nBUG-10 #comment Resolved #assign jdoe"
    commands = @parser.parse(text)

    rak_commands = commands.select { |c| c.issue_key == 'RAK-1' }
    bug_commands = commands.select { |c| c.issue_key == 'BUG-10' }

    assert_equal 2, rak_commands.size
    assert_equal 2, bug_commands.size

    assert_equal :done, rak_commands[0].action
    assert_equal :time, rak_commands[1].action
    assert_equal '2h', rak_commands[1].value

    assert_equal :comment, bug_commands[0].action
    assert_equal 'Resolved', bug_commands[0].value
    assert_equal :assign, bug_commands[1].action
    assert_equal 'jdoe', bug_commands[1].value
  end

  def test_realistic_commit_message
    text = "RAK-1 #comment Fixed null pointer exception in user service\n#done #time 1h 30m"
    commands = @parser.parse(text)

    assert_equal 3, commands.size
    assert_equal 'RAK-1', commands[0].issue_key
    assert_equal :comment, commands[0].action
    assert_equal 'Fixed null pointer exception in user service', commands[0].value
    assert_equal :done, commands[1].action
    assert_equal :time, commands[2].action
  end

  def test_standalone_number_not_treated_as_issue_key
    commands = @parser.parse('Fixed issue #123 #comment test')
    assert_equal 0, commands.size
  end

  def test_parses_only_known_commands
    commands = @parser.parse('RAK-1 #todo something')
    assert_equal 0, commands.size
  end

  def test_parses_in_progress_command_as_done_alias
    commands = @parser.parse('RAK-1 #in-progress')
    assert_equal 1, commands.size
    assert_equal :done, commands[0].action
    assert_equal 'RAK-1', commands[0].issue_key
  end

  def test_parses_resolve_command_as_done_alias
    commands = @parser.parse('RAK-1 #resolve')
    assert_equal 1, commands.size
    assert_equal :done, commands[0].action
    assert_equal 'RAK-1', commands[0].issue_key
  end

  def test_in_progress_and_done_both_work
    commands = @parser.parse('RAK-1 #in-progress and RAK-2 #done')
    assert_equal 2, commands.size
    assert_equal :done, commands[0].action
    assert_equal 'RAK-1', commands[0].issue_key
    assert_equal :done, commands[1].action
    assert_equal 'RAK-2', commands[1].issue_key
  end
end
