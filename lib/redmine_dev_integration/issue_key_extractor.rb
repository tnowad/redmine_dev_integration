# frozen_string_literal: true

module RedmineDevIntegration
  class IssueKeyExtractor
    Match = Struct.new(:key, :matched_text, :source, keyword_init: true)

    ISSUE_KEY_PATTERN = /
      (?<![A-Za-z0-9])
      ([A-Za-z][A-Za-z0-9]{1,15}-\d+)
      (?![A-Za-z0-9])
    /ix.freeze

    def self.extract(texts)
      new.extract(texts)
    end

    def self.extract_matches(texts)
      new.extract_matches(texts)
    end

    def extract(texts)
      extract_matches(texts).map(&:key)
    end

    def extract_matches(texts)
      Array(texts).flat_map { |text| scan_text(text) }.uniq(&:key)
    end

    private

    def scan_text(text)
      return [] if text.nil?

      text.to_s.scan(ISSUE_KEY_PATTERN).map do |match|
        raw = match.first
        Match.new(key: raw.upcase, matched_text: raw, source: text)
      end
    end
  end
end
