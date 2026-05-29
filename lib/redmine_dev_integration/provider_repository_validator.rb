# frozen_string_literal: true

module RedmineDevIntegration
  class ProviderRepositoryValidator
    Result = Struct.new(:errors, :normalized_attributes, keyword_init: true) do
      def valid?
        errors.empty?
      end
    end

    PROVIDERS = %w[github gitlab bitbucket].freeze
    URL_PATTERN = %r{\Ahttps?://\S+\z}.freeze

    def self.call(project:, attributes:, existing_repository: nil)
      new(project: project, attributes: attributes, existing_repository: existing_repository).call
    end

    def initialize(project:, attributes:, existing_repository: nil)
      @project = project
      @attributes = attributes
      @existing_repository = existing_repository
    end

    def call
      validate!
      Result.new(errors: errors, normalized_attributes: normalized_attributes)
    end

    def self.human_attribute_name(attribute, _options = {})
      attribute.to_s.tr('_', ' ').capitalize
    end

    def read_attribute_for_validation(attribute)
      normalized_attributes[attribute.to_sym]
    end

    private

    attr_reader :project, :attributes, :existing_repository

    def errors
      @errors ||= ActiveModel::Errors.new(self)
    end

    def normalized_attributes
      @normalized_attributes ||= begin
        raw_attributes = attributes.respond_to?(:to_h) ? attributes.to_h : {}
        raw_attributes = raw_attributes.to_h if raw_attributes.respond_to?(:to_h) && !raw_attributes.is_a?(Hash)
        raw_attributes = raw_attributes.stringify_keys if raw_attributes.respond_to?(:stringify_keys)

        {
          provider: normalize_string(attribute_value(raw_attributes, 'provider')),
          repository_url_or_path: normalize_string(attribute_value(raw_attributes, 'repository_url_or_path')),
          provider_repository_id: normalize_string(attribute_value(raw_attributes, 'provider_repository_id')),
          owner: normalize_string(attribute_value(raw_attributes, 'owner')),
          repo_name: normalize_string(attribute_value(raw_attributes, 'repo_name')),
          full_name: normalize_string(attribute_value(raw_attributes, 'full_name')),
          url: normalize_string(attribute_value(raw_attributes, 'url')),
          redmine_repository_id: normalize_string(attribute_value(raw_attributes, 'redmine_repository_id')),
          active: normalize_boolean(attribute_value(raw_attributes, 'active'))
        }.then { |normalized| apply_repository_parser(normalized) }
      end
    end

    def validate!
      validate_provider
      validate_provider_repository_id
      validate_owner
      validate_repo_name
      validate_full_name
      validate_url
      validate_redmine_repository
    end

    def validate_provider
      provider = normalized_attributes[:provider]

      unless PROVIDERS.include?(provider)
        errors.add(:provider, t('redmine_dev_integration.provider_repository_validator.errors.invalid_provider', default: 'provider is invalid'))
        return
      end

      return if provider_enabled?(provider)

      errors.add(:provider, t('redmine_dev_integration.provider_repository_validator.errors.provider_disabled', default: 'provider is disabled'))
    end

    def validate_provider_repository_id
      provider_repository_id = normalized_attributes[:provider_repository_id]

      if provider_repository_id.blank?
        errors.add(
          :provider_repository_id,
          t('redmine_dev_integration.provider_repository_validator.errors.missing_provider_repository_id', default: 'provider repository ID is required')
        )
        return
      end

      if provider_repository_id.match?(/\s/)
        errors.add(
          :provider_repository_id,
          t('redmine_dev_integration.provider_repository_validator.errors.invalid_provider_repository_id', default: 'provider repository ID is invalid')
        )
        return
      end

      if normalized_attributes[:provider] == 'github' && provider_repository_id !~ /\A\d+\z/
        errors.add(
          :provider_repository_id,
          t('redmine_dev_integration.provider_repository_validator.errors.invalid_github_provider_repository_id', default: 'Github provider repository ID must be numeric')
        )
        return
      end

      if normalized_attributes[:provider] == 'bitbucket' && provider_repository_id !~ /\A\{?[\da-f]{8}-[\da-f]{4}-[\da-f]{4}-[\da-f]{4}-[\da-f]{12}\}?\z/i
        errors.add(
          :provider_repository_id,
          t('redmine_dev_integration.provider_repository_validator.errors.invalid_bitbucket_provider_repository_id', default: 'Bitbucket provider repository ID must be a valid UUID')
        )
        return
      end

      return if errors[:provider].present?

      duplicate_scope = ExternalRepository.where(
        provider: normalized_attributes[:provider],
        provider_repository_id: provider_repository_id
      )
      duplicate_scope = duplicate_scope.where.not(id: existing_repository.id) if existing_repository&.id.present?

      return unless duplicate_scope.exists?

      errors.add(
        :provider_repository_id,
        t('redmine_dev_integration.provider_repository_validator.errors.repository_already_connected', default: 'repository already connected')
      )
    end

    def validate_owner
      return if normalized_attributes[:owner].present?

      errors.add(:owner, t('redmine_dev_integration.provider_repository_validator.errors.missing_owner', default: 'owner is required'))
    end

    def validate_repo_name
      return if normalized_attributes[:repo_name].present?

      errors.add(:repo_name, t('redmine_dev_integration.provider_repository_validator.errors.missing_repo_name', default: 'repo name is required'))
    end

    def validate_full_name
      full_name = normalized_attributes[:full_name]
      return if full_name.present? && full_name.match?(%r{\A[^/\s]+(?:/[^/\s]+)+\z})

      errors.add(:full_name, t('redmine_dev_integration.provider_repository_validator.errors.missing_full_name', default: 'full name is required'))
    end

    def validate_url
      url = normalized_attributes[:url]
      return if url.present? && url.match?(URL_PATTERN)

      errors.add(:url, t('redmine_dev_integration.provider_repository_validator.errors.invalid_url', default: 'URL must be HTTP or HTTPS'))
    end

    def validate_redmine_repository
      redmine_repository_id = normalized_attributes[:redmine_repository_id]
      return if redmine_repository_id.blank?
      return if project.present? && project.repositories.exists?(id: redmine_repository_id)

      errors.add(
        :redmine_repository_id,
        t('redmine_dev_integration.provider_repository_validator.errors.invalid_redmine_repository_id', default: 'SCM repository must belong to this project')
      )
    end

    def provider_enabled?(provider)
      setting = Setting.plugin_redmine_dev_integration
      return true unless setting.is_a?(Hash)

      key = "#{provider}_provider_enabled"
      value = if setting.key?(key)
        setting[key]
      elsif setting.key?(key.to_sym)
        setting[key.to_sym]
      end

      return true if value.nil?

      value == '1' || value == true
    end

    def normalize_string(value)
      return nil if value.nil?

      string = value.to_s.strip
      string.presence
    end

    def attribute_value(attributes_hash, key)
      return attributes_hash[key] if attributes_hash.key?(key)

      symbol_key = key.to_sym
      return attributes_hash[symbol_key] if attributes_hash.key?(symbol_key)

      nil
    end

    def normalize_boolean(value)
      return nil if value.nil?

      if defined?(ActiveModel::Type::Boolean)
        ActiveModel::Type::Boolean.new.cast(value)
      else
        value == true || value.to_s == '1'
      end
    end

    def apply_repository_parser(normalized)
      repository_input = normalized.delete(:repository_url_or_path)
      parsed = ProviderRepositoryParser.call(provider: normalized[:provider], repository: repository_input)
      return normalized if parsed.nil?

      parsed.to_h.each do |attribute, value|
        normalized[attribute] = value if normalized[attribute].blank?
      end

      normalized
    end

    def t(key, default:)
      I18n.t(key, default: default)
    end
  end
end
