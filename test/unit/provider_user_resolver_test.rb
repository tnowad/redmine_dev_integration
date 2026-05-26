# frozen_string_literal: true

require_relative '../test_helper'

class ProviderUserResolverTest < ActiveSupport::TestCase
  fixtures :users

  def setup
    @user = users(:users_001)
    @user2 = users(:users_002)
  end

  def test_resolves_by_provider_user_id
    ExternalProviderUserMapping.create!(
      provider: 'github',
      provider_user_id: '12345',
      provider_login: 'ghuser',
      user: @user
    )

    result = RedmineDevIntegration::ProviderUserResolver.call(
      provider: 'github',
      provider_login: 'different_login',
      provider_user_id: '12345'
    )

    assert_equal @user, result
  end

  def test_resolves_by_provider_login_fallback
    ExternalProviderUserMapping.create!(
      provider: 'github',
      provider_user_id: '12345',
      provider_login: 'ghuser',
      user: @user
    )

    result = RedmineDevIntegration::ProviderUserResolver.call(
      provider: 'github',
      provider_login: 'ghuser',
      provider_user_id: 'unknown_id'
    )

    assert_equal @user, result
  end

  def test_returns_nil_when_no_mapping
    result = RedmineDevIntegration::ProviderUserResolver.call(
      provider: 'github',
      provider_login: 'unknown',
      provider_user_id: 'unknown'
    )

    assert_nil result
  end

  def test_returns_nil_when_only_different_provider_matches
    ExternalProviderUserMapping.create!(
      provider: 'gitlab',
      provider_user_id: '12345',
      provider_login: 'gluser',
      user: @user
    )

    result = RedmineDevIntegration::ProviderUserResolver.call(
      provider: 'github',
      provider_login: 'gluser',
      provider_user_id: '12345'
    )

    assert_nil result
  end

end
