# frozen_string_literal: true

require_relative '../test_helper'

class GitlabWebhookTokenVerifierTest < ActiveSupport::TestCase
  def setup
    @token = 'topsecret'
    @verifier = RedmineDevIntegration::GitlabWebhookTokenVerifier.new(expected_token: @token)
  end

  def test_rejects_missing_expected_token
    verifier = RedmineDevIntegration::GitlabWebhookTokenVerifier.new(expected_token: nil)

    assert_not verifier.valid?(token: @token)
  end

  def test_rejects_missing_token
    assert_not @verifier.valid?(token: nil)
  end

  def test_rejects_wrong_token
    assert_not @verifier.valid?(token: 'other-secret')
  end

  def test_accepts_valid_token
    assert @verifier.valid?(token: @token)
  end

  def test_class_helper_validates_token
    assert RedmineDevIntegration::GitlabWebhookTokenVerifier.valid?(
      token: @token,
      expected_token: @token
    )
  end
end
