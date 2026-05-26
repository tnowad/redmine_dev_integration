# frozen_string_literal: true

require_relative '../test_helper'

class ExternalProviderUserMappingTest < ActiveSupport::TestCase
  fixtures :users

  def setup
    @user = users(:users_001)
    @mapping = ExternalProviderUserMapping.new(
      provider: 'github',
      provider_user_id: '12345',
      provider_login: 'testuser',
      user: @user
    )
  end

  def test_valid_mapping
    assert_predicate @mapping, :valid?
  end

  def test_requires_provider
    @mapping.provider = nil

    assert_not_predicate @mapping, :valid?
    assert_includes @mapping.errors[:provider], "cannot be blank"
  end

  def test_requires_provider_user_id
    @mapping.provider_user_id = nil

    assert_not_predicate @mapping, :valid?
    assert_includes @mapping.errors[:provider_user_id], "cannot be blank"
  end

  def test_requires_provider_login
    @mapping.provider_login = nil

    assert_not_predicate @mapping, :valid?
    assert_includes @mapping.errors[:provider_login], "cannot be blank"
  end

  def test_requires_user
    @mapping.user = nil

    assert_not_predicate @mapping, :valid?
    assert @mapping.errors[:user].present? || @mapping.errors[:user_id].present?
  end

  def test_invalid_provider_fails
    @mapping.provider = 'bitbucket'

    assert_not_predicate @mapping, :valid?
    assert_includes @mapping.errors[:provider], 'is not included in the list'
  end

  def test_enforces_uniqueness_of_provider_and_provider_user_id
    @mapping.save!

    duplicate = @mapping.dup
    assert_not_predicate duplicate, :valid?
    assert_includes duplicate.errors[:provider_user_id], 'has already been taken'
  end

  def test_allows_same_provider_user_id_on_different_provider
    @mapping.save!

    duplicate = ExternalProviderUserMapping.new(
      provider: 'gitlab',
      provider_user_id: '12345',
      provider_login: 'testuser',
      user: @user
    )

    assert_predicate duplicate, :valid?
  end

  def test_belongs_to_user
    @mapping.save!

    assert_equal @user, @mapping.user
  end
end
