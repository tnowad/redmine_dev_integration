# frozen_string_literal: true

module RedmineDevIntegration
  class PushCommitTextExtractor
    def self.extract(commits)
      return [] unless commits.is_a?(Array)

      commits.map { |c| c['message'] if c.is_a?(Hash) }.compact
    end
  end
end
