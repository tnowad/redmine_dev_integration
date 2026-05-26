# frozen_string_literal: true

require 'strscan'

module RedmineDevIntegration
  class SmartCommitParser
    Command = Struct.new(:issue_key, :action, :value, keyword_init: true)

    COMMENT_COMMAND = '#comment'
    DONE_COMMAND    = '#done'
    IN_PROGRESS_COMMAND = '#in-progress'
    RESOLVE_COMMAND = '#resolve'
    TIME_COMMAND    = '#time'
    ASSIGN_COMMAND  = '#assign'

    COMMAND_PATTERN = /#(?:comment|done|in-progress|resolve|time|assign)\b/i

    def self.parse(text)
      new.parse(text)
    end

    def parse(text)
      return [] if text.blank?

      commands = []
      scanner = StringScanner.new(text.to_s)
      current_issue_key = nil

      while !scanner.eos?
        if (key = scanner.scan(IssueKeyExtractor::ISSUE_KEY_PATTERN))
          current_issue_key = key.strip.upcase
          next
        end

        if scanner.scan(/#comment\b/i)
          next unless current_issue_key
          value = extract_until_next_command_or_key(scanner)
          commands << Command.new(issue_key: current_issue_key, action: :comment, value: value)
          next
        end

        if scanner.scan(/#done\b/i)
          next unless current_issue_key
          commands << Command.new(issue_key: current_issue_key, action: :done, value: nil)
          next
        end

        if scanner.scan(/#in-progress\b/i)
          next unless current_issue_key
          commands << Command.new(issue_key: current_issue_key, action: :done, value: nil)
          next
        end

        if scanner.scan(/#resolve\b/i)
          next unless current_issue_key
          commands << Command.new(issue_key: current_issue_key, action: :done, value: nil)
          next
        end

        if scanner.scan(/#time\b/i)
          next unless current_issue_key
          value = extract_until_next_command_or_key(scanner)
          commands << Command.new(issue_key: current_issue_key, action: :time, value: value)
          next
        end

        if scanner.scan(/#assign\b/i)
          next unless current_issue_key
          value = extract_assign_value(scanner)
          commands << Command.new(issue_key: current_issue_key, action: :assign, value: value)
          next
        end

        scanner.getch
      end

      commands
    end

    private

    def extract_time_value(scanner)
      extract_until_next_command_or_key(scanner)
    end

    def extract_comment_value(scanner)
      extract_until_next_command_or_key(scanner)
    end

    def extract_assign_value(scanner)
      skip_whitespace(scanner)
      value = +''
      loop do
        break if scanner.eos?
        char = scanner.peek(1)
        break if char =~ /\s/
        break if scanner.check(COMMAND_PATTERN) || scanner.check(IssueKeyExtractor::ISSUE_KEY_PATTERN)
        value << scanner.getch
      end
      value.strip.presence
    end

    def extract_until_next_command_or_key(scanner)
      value = +''
      loop do
        break if scanner.eos?
        if scanner.check(COMMAND_PATTERN) || scanner.check(IssueKeyExtractor::ISSUE_KEY_PATTERN)
          break
        end
        value << scanner.getch
      end
      value.strip.presence
    end

    def skip_whitespace(scanner)
      scanner.scan(/\s+/)
    end
  end
end
