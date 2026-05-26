# frozen_string_literal: true

module RedmineDevIntegration
  class GitlabWebhookTokenVerifier
    def self.valid?(token:, expected_token:)
      new(expected_token: expected_token).valid?(token: token)
    end

    def initialize(expected_token:)
      @expected_token = expected_token.to_s
    end

    def valid?(token:)
      return false if expected_token.empty? || token.blank?

      secure_compare(expected_token, token.to_s)
    end

    private

    attr_reader :expected_token

    def secure_compare(a, b)
      return false unless a.bytesize == b.bytesize

      if defined?(ActiveSupport::SecurityUtils) && ActiveSupport::SecurityUtils.respond_to?(:secure_compare)
        ActiveSupport::SecurityUtils.secure_compare(a, b)
      else
        a == b
      end
    end
  end
end
