# frozen_string_literal: true

require 'json'

module RedmineDevIntegration
  class GitlabReleaseProcessor
    def initialize; end

    def call(external_provider_event)
      payload = parse_payload(external_provider_event.payload)
      return false unless payload.is_a?(Hash)
      return false unless external_provider_event.provider == 'gitlab'
      return false unless external_provider_event.event_type == 'Release Hook'

      repository = ExternalRepositoryResolver.gitlab(payload)
      return false unless repository

      tag_name = payload['tag']
      return false if tag_name.blank?

      release = ExternalRelease.find_or_initialize_by(
        provider: 'gitlab',
        external_repository: repository,
        name: tag_name
      )

      release.tag_name = tag_name
      release.body = payload['description']
      release.url = payload['url']
      release.status = 'published'
      release.author_login = payload.dig('commit', 'author', 'name')
      release.released_at = payload['released_at'] || payload['created_at']
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
