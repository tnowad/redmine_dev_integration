# frozen_string_literal: true

require_relative '../test_helper'

class GitHubWebhookSignatureVerifierTest < ActiveSupport::TestCase
  def setup
    @secret = 'topsecret'
    @payload = '{"action":"opened"}'
    @verifier = RedmineDevIntegration::GitHubWebhookSignatureVerifier.new(secret: @secret)
  end

  def test_rejects_missing_secret
    verifier = RedmineDevIntegration::GitHubWebhookSignatureVerifier.new(secret: nil)

    assert_not verifier.valid?(payload: @payload, signature: valid_signature)
  end

  def test_rejects_missing_signature
    assert_not @verifier.valid?(payload: @payload, signature: nil)
  end

  def test_rejects_invalid_signature_format
    assert_not @verifier.valid?(payload: @payload, signature: 'not-a-github-signature')
    assert_not @verifier.valid?(payload: @payload, signature: 'sha1=abc')
    assert_not @verifier.valid?(payload: @payload, signature: 'sha256=xyz')
  end

  def test_rejects_wrong_digest
    assert_not @verifier.valid?(payload: @payload, signature: signature_for('different secret'))
  end

  def test_accepts_valid_signature
    assert @verifier.valid?(payload: @payload, signature: valid_signature)
  end

  def test_class_helper_validates_signature
    assert RedmineDevIntegration::GitHubWebhookSignatureVerifier.valid?(
      payload: @payload,
      signature: valid_signature,
      secret: @secret
    )
  end

  private

  def valid_signature
    signature_for(@secret)
  end

  def signature_for(secret)
    digest = OpenSSL::HMAC.hexdigest('SHA256', secret, @payload)
    "sha256=#{digest}"
  end
end
