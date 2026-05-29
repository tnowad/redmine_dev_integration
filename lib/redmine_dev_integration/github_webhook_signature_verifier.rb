# frozen_string_literal: true

require 'openssl'

module RedmineDevIntegration
  class GithubWebhookSignatureVerifier
    SIGNATURE_PREFIX = 'sha256='

    def self.valid?(payload:, signature:, secret:)
      new(secret: secret).valid?(payload: payload, signature: signature)
    end

    def initialize(secret:)
      @secret = secret.to_s
    end

    def valid?(payload:, signature:)
      return false if secret.empty? || signature.blank?

      digest = extract_digest(signature.to_s)
      return false if digest.nil?

      expected = OpenSSL::HMAC.hexdigest('SHA256', secret, payload.to_s)
      secure_compare(expected, digest)
    end

    private

    attr_reader :secret

    def extract_digest(signature)
      return nil unless signature.start_with?(SIGNATURE_PREFIX)

      digest = signature.delete_prefix(SIGNATURE_PREFIX)
      return nil unless digest.match?(/\A\h{64}\z/i)

      digest.downcase
    end

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
