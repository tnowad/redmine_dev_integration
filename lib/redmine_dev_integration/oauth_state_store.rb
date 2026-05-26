# frozen_string_literal: true

module RedmineDevIntegration
  class OauthStateStore
    def self.generate(provider)
      state = SecureRandom.hex(32)
      cache.write("oauth_state:#{state}", provider, expires_in: 10.minutes)
      state
    end

    def self.verify(state, provider)
      stored = cache.read("oauth_state:#{state}")
      cache.delete("oauth_state:#{state}")
      stored == provider
    end

    def self.cache
      @cache ||= if Rails.cache.respond_to?(:write) && Rails.cache.class != ActiveSupport::Cache::NullStore
                   Rails.cache
                 else
                   ActiveSupport::Cache::MemoryStore.new(expires_in: 10.minutes)
                 end
    end
  end
end
