# frozen_string_literal: true

require 'json'

module RedmineDevIntegration
  class GitHubReleaseProcessor
    def initialize; end

    def call(external_provider_event)
      payload = parse_payload(external_provider_event.payload)
      return false unless payload.is_a?(Hash)
      return false unless external_provider_event.provider == 'github'
      return false unless external_provider_event.event_type == 'release'

      repository = ExternalRepositoryResolver.github(payload)
      return false unless repository

      release_data = payload['release'] || {}
      return false if release_data['tag_name'].blank?

      action = payload['action']
      return false unless %w[published created].include?(action)

      release = ExternalRelease.find_or_initialize_by(
        provider: 'github',
        external_repository: repository,
        name: release_data['tag_name']
      )

      release.tag_name = release_data['tag_name']
      release.body = release_data['body']
      release.url = release_data['html_url']
      release.status = release_data['draft'] ? 'draft' : 'published'
      release.author_login = release_data.dig('author', 'login')
      release.released_at = release_data['published_at'] || release_data['created_at']
      release.save!
      release.link_issues_from_deployments
      true
    end

    private

    def parse_payload(payload)
      return payload if payload.is_a?(Hash)
      return {} if payload.blank?

      JSON.parse(payload)
    rescue JSON::ParserError
      nil
    end
  end
end
