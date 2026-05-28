# frozen_string_literal: true

module RedmineDevIntegration
  class IssueLinker
    Result = Struct.new(:matched_keys, :issue_ids, keyword_init: true)

    def initialize(extractor: IssueKeyExtractor.new)
      @extractor = extractor
    end

    def link(texts)
      matched_keys = extract_keys(texts)
      issue_ids = resolve_issue_ids(matched_keys)
      Result.new(matched_keys: matched_keys, issue_ids: issue_ids)
    end

    private

    attr_reader :extractor

    def extract_keys(texts)
      extractor.extract(texts).uniq
    end

    def resolve_issue_ids(keys)
      return missing_companion_warning unless issue_find_by_issue_key_available?

      normalized = keys.map { |k| k.to_s.strip.upcase }.reject(&:blank?).uniq
      return [] if normalized.empty?

      valid_keys = normalized.select { |k| k.match?(/\A[A-Z][A-Z0-9]{1,15}-\d+\z/) }
      return [] if valid_keys.empty?

      Issue.where(issue_key: valid_keys).pluck(:issue_key, :id)
           .each_with_object({}) { |(k, id), h| h[k.upcase] = id }
           .values_at(*normalized)
           .compact
           .uniq
    end

    def issue_find_by_issue_key_available?
      defined?(Issue) && Issue.respond_to?(:find_by_issue_key)
    end

    def missing_companion_warning
      Rails.logger.warn(
        '[redmine_dev_integration] Issue.find_by_issue_key not available. ' \
        'Install redmine_issue_keys plugin to enable issue linking from branches/PRs.'
      )
      []
    end
  end
end
