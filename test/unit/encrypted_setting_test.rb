# frozen_string_literal: true

require_relative '../test_helper'

class EncryptedSettingTest < ActiveSupport::TestCase
  setup do
    @secret = Rails.application.secret_key_base
  end

  test 'encrypt and decrypt roundtrip with plain string' do
    original = 'my-secret-token'
    encrypted = RedmineDevIntegration::EncryptedSetting.encrypt(original)
    assert_not_nil encrypted
    refute_equal original, encrypted

    decrypted = RedmineDevIntegration::EncryptedSetting.decrypt(encrypted)
    assert_equal original, decrypted
  end

  test 'encrypt and decrypt roundtrip with special characters' do
    original = '!@#$%^&*()_+{}|:"<>?`-=[];\',./~'
    encrypted = RedmineDevIntegration::EncryptedSetting.encrypt(original)
    decrypted = RedmineDevIntegration::EncryptedSetting.decrypt(encrypted)
    assert_equal original, decrypted
  end

  test 'encrypt returns nil for nil value' do
    assert_nil RedmineDevIntegration::EncryptedSetting.encrypt(nil)
  end

  test 'encrypt returns nil for blank value' do
    assert_nil RedmineDevIntegration::EncryptedSetting.encrypt('')
  end

  test 'decrypt returns nil for nil value' do
    assert_nil RedmineDevIntegration::EncryptedSetting.decrypt(nil)
  end

  test 'decrypt returns nil for blank value' do
    assert_nil RedmineDevIntegration::EncryptedSetting.decrypt('')
  end

  test 'decrypt returns nil for invalid encrypted data' do
    assert_nil RedmineDevIntegration::EncryptedSetting.decrypt('not-valid-encrypted-data')
  end

  test 'decrypt returns nil for tampered data' do
    original = 'tamper-test-token'
    encrypted = RedmineDevIntegration::EncryptedSetting.encrypt(original)
    tampered = encrypted.reverse
    assert_nil RedmineDevIntegration::EncryptedSetting.decrypt(tampered)
  end

  test 'encryption key is deterministic' do
    key1 = RedmineDevIntegration::EncryptedSetting.encryption_key
    key2 = RedmineDevIntegration::EncryptedSetting.encryption_key
    assert_equal key1, key2
    assert_equal 32, key1.bytesize
  end
end
