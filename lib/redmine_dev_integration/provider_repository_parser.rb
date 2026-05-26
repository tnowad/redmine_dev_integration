# frozen_string_literal: true

require 'uri'

module RedmineDevIntegration
  class ProviderRepositoryParser
    Result = Struct.new(:provider, :owner, :repo_name, :full_name, :url, keyword_init: true) do
      def to_h
        {
          provider: provider,
          owner: owner,
          repo_name: repo_name,
          full_name: full_name,
          url: url
        }
      end
    end

    SUPPORTED_PROVIDERS = %w[github gitlab bitbucket].freeze

    def self.call(provider:, repository:)
      new(provider: provider, repository: repository).call
    end

    def initialize(provider:, repository:)
      @provider = normalize_string(provider)
      @repository = normalize_string(repository)
    end

    def call
      return nil if provider.blank? || repository.blank?
      return nil unless SUPPORTED_PROVIDERS.include?(provider)

      path = repository_path
      return nil if path.blank?

      segments = path.split('/').reject(&:blank?)
      return nil if segments.empty?

      case provider
      when 'github'
        parse_github(segments)
      when 'gitlab'
        parse_gitlab(segments)
      when 'bitbucket'
        parse_bitbucket(segments)
      end
    rescue StandardError
      nil
    end

    private

    attr_reader :provider, :repository

    def parse_github(segments)
      return nil unless segments.length == 2

      owner, repo_name = segments
      build_result(owner: owner, repo_name: repo_name, full_name: "#{owner}/#{repo_name}")
    end

    def parse_gitlab(segments)
      return nil if segments.length < 2

      repo_name = segments.last
      owner = segments[0...-1].join('/')
      return nil if owner.blank?

      build_result(owner: owner, repo_name: repo_name, full_name: segments.join('/'))
    end

    def parse_bitbucket(segments)
      return nil unless segments.length == 2

      owner, repo_name = segments
      build_result(owner: owner, repo_name: repo_name, full_name: "#{owner}/#{repo_name}")
    end

    def build_result(owner:, repo_name:, full_name:)
      Result.new(
        provider: provider,
        owner: owner,
        repo_name: repo_name,
        full_name: full_name,
        url: canonical_url(full_name)
      )
    end

    def canonical_url(full_name)
      "https://#{host}/#{full_name}"
    end

    def host
      case provider
      when 'github'
        'github.com'
      when 'gitlab'
        'gitlab.com'
      when 'bitbucket'
        'bitbucket.org'
      end
    end

    def repository_path
      return github_or_gitlab_url_path if url_like?
      return scp_like_path if scp_like?

      repository
    end

    def url_like?
      repository.match?(%r{\Ahttps?://}i)
    end

    def scp_like?
      repository.match?(%r{\A[^@\s]+@[^:\s]+:.+})
    end

    def github_or_gitlab_url_path
      uri = URI.parse(repository)
      return nil unless uri.host.present?
      return nil unless host_matches_provider?(uri.host)

      normalize_path(uri.path)
    rescue URI::InvalidURIError
      nil
    end

    def scp_like_path
      match = repository.match(%r{\A[^@\s]+@([^:\s]+):(.+)\z})
      return nil unless match
      return nil unless host_matches_provider?(match[1])

      normalize_path(match[2])
    end

    def host_matches_provider?(host)
      case provider
      when 'github'
        host.to_s == 'github.com'
      when 'gitlab'
        host.to_s == 'gitlab.com'
      when 'bitbucket'
        host.to_s == 'bitbucket.org'
      else
        false
      end
    end

    def normalize_path(path)
      value = path.to_s.sub(%r{\A/}, '')
      value = value.sub(%r{\.git\z}, '')
      value = value.sub(%r{/\z}, '')
      value.presence
    end

    def normalize_string(value)
      return nil if value.nil?

      string = value.to_s.strip
      string.presence
    end
  end
end
