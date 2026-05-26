# frozen_string_literal: true

module RedmineDevIntegration
  class EncryptedSetting
    def self.encrypt(value)
      return nil if value.blank?
      encryptor.encrypt_and_sign(value)
    end

    def self.decrypt(value)
      return nil if value.blank?
      encryptor.decrypt_and_verify(value)
    rescue ActiveSupport::MessageEncryptor::InvalidMessage, ActiveSupport::MessageVerifier::InvalidSignature
      nil
    end

    def self.encryptor
      ActiveSupport::MessageEncryptor.new(encryption_key)
    end

    def self.encryption_key
      secret = Rails.application.secret_key_base
      ActiveSupport::KeyGenerator.new(secret).generate_key('redmine_dev_integration_oauth', 32)
    end
  end
end
