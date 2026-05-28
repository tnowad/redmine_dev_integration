# frozen_string_literal: true

require 'json'

module RedmineDevIntegration
  class GitHubPullRequestReviewProcessor
    def initialize; end

    def call(external_provider_event)
      payload = parse_payload(external_provider_event.payload)
      return false unless payload.is_a?(Hash)
      return false unless external_provider_event.provider == 'github'
      return false unless external_provider_event.event_type == 'pull_request_review'

      repository = RedmineDevIntegration::ExternalRepositoryResolver.github(payload)
      return false unless repository

      pr_data = payload['pull_request'] || {}
      review_data = payload['review'] || {}

      pr = ExternalPullRequest.find_by(
        provider: 'github',
        external_repository: repository,
        number: pr_data['number']
      )
      return false unless pr

      return false if review_data['id'].blank?

      review = ExternalReview.find_or_initialize_by(
        provider: 'github',
        external_pull_request: pr,
        provider_review_id: review_data['id'].to_s
      )

      review.reviewer_login = review_data.dig('user', 'login')
      review.reviewer_name = review_data.dig('user', 'login')
      review.state = review_data['state'].to_s.upcase
      review.body = review_data['body']
      review.submitted_at = time_value(review_data['submitted_at'])
      review.save!
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

    def time_value(value)
      return if value.blank?

      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
