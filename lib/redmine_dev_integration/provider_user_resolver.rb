# frozen_string_literal: true

module RedmineDevIntegration
  class ProviderUserResolver
    class << self
      def call(provider:, provider_login:, provider_user_id: nil)
        if provider_user_id.present?
          mapping = ExternalProviderUserMapping.find_by(provider: provider, provider_user_id: provider_user_id)
          return mapping.user if mapping
        end

        mapping = ExternalProviderUserMapping.find_by(provider: provider, provider_login: provider_login)
        return mapping.user if mapping

        nil
      end

      def with_resolved_user(provider:, provider_login:, provider_user_id: nil, &block)
        resolved = call(provider: provider, provider_login: provider_login, provider_user_id: provider_user_id)
        original_user = User.current
        User.current = resolved if resolved
        yield
      ensure
        User.current = original_user
      end
    end
  end
end
