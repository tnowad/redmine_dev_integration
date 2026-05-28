# frozen_string_literal: true

require_relative '../test_helper'

class GitHubPullRequestReviewProcessorTest < ActiveSupport::TestCase
  fixtures :projects, :repositories

  def setup
    @processor = RedmineDevIntegration::GitHubPullRequestReviewProcessor.new
    @external_repository = ExternalRepository.create!(
      provider: 'github',
      provider_repository_id: '123',
      owner: 'redmine',
      repo_name: 'redmine_dev_integration',
      full_name: 'redmine/redmine_dev_integration',
      url: 'https://github.com/redmine/redmine_dev_integration',
      redmine_project: projects(:projects_001)
    )

    @pull_request = ExternalPullRequest.create!(
      provider: 'github',
      external_repository: @external_repository,
      number: 42,
      title: 'Fix login feature',
      body: 'Implementation of login feature',
      url: 'https://github.com/redmine/redmine_dev_integration/pull/42',
      state: 'open',
      author_login: 'author1',
      source_branch: 'feature/login',
      target_branch: 'main',
      merged: false
    )
  end

  def review_payload(overrides = {})
    {
      action: 'submitted',
      review: {
        id: 1001,
        user: { login: 'reviewer1', id: 200 },
        body: 'Looks good to me!',
        state: 'approved',
        submitted_at: '2026-01-15T10:00:00Z'
      },
      pull_request: {
        id: 1000,
        number: 42,
        title: 'Fix login feature',
        state: 'open',
        html_url: 'https://github.com/redmine/redmine_dev_integration/pull/42',
        user: { login: 'author1' },
        head: { ref: 'feature/login', sha: 'abc123' },
        base: { ref: 'main', sha: 'base999' }
      },
      repository: {
        id: 123,
        html_url: 'https://github.com/redmine/redmine_dev_integration'
      },
      sender: { login: 'reviewer1' }
    }.deep_merge(overrides)
  end

  def build_event(attributes = {})
    payload_data = review_payload
    ExternalProviderEvent.new({
      provider: 'github',
      delivery_id: "delivery-#{SecureRandom.hex(4)}",
      event_type: 'pull_request_review',
      payload: JSON.generate(payload_data),
      status: 'pending'
    }.merge(attributes))
  end

  def test_creates_review_for_approved_pull_request_review
    event = build_event
    assert_difference 'ExternalReview.count', 1 do
      assert @processor.call(event)
    end

    review = ExternalReview.last
    assert_equal 'github', review.provider
    assert_equal @pull_request, review.external_pull_request
    assert_equal '1001', review.provider_review_id
    assert_equal 'reviewer1', review.reviewer_login
    assert_equal 'reviewer1', review.reviewer_name
    assert_equal 'APPROVED', review.state
    assert_equal 'Looks good to me!', review.body
    assert_equal Time.zone.parse('2026-01-15T10:00:00Z'), review.submitted_at
  end

  def test_creates_review_for_changes_requested
    event = build_event(payload: JSON.generate(review_payload({
      review: { id: 1002, user: { login: 'reviewer2' }, state: 'changes_requested', submitted_at: '2026-01-15T11:00:00Z' }
    })))

    assert_difference 'ExternalReview.count', 1 do
      assert @processor.call(event)
    end

    review = ExternalReview.last
    assert_equal 'CHANGES_REQUESTED', review.state
    assert_equal 'reviewer2', review.reviewer_login
  end

  def test_updates_existing_review_on_duplicate_provider_review_id
    ExternalReview.create!(
      provider: 'github',
      external_pull_request: @pull_request,
      provider_review_id: '1001',
      reviewer_login: 'reviewer1',
      state: 'COMMENTED',
      submitted_at: 1.hour.ago
    )

    event = build_event
    assert_no_difference 'ExternalReview.count' do
      assert @processor.call(event)
    end

    review = ExternalReview.find_by!(provider_review_id: '1001')
    assert_equal 'APPROVED', review.state
    assert_equal 'Looks good to me!', review.body
  end

  def test_returns_false_when_pr_not_found
    event = build_event(payload: JSON.generate(review_payload({
      pull_request: { number: 999, id: 999, title: 'Unknown' }
    })))

    assert_no_difference 'ExternalReview.count' do
      assert_equal false, @processor.call(event)
    end
  end

  def test_returns_false_when_repository_not_found
    event = build_event(payload: JSON.generate(review_payload({
      repository: { id: 99999, html_url: 'https://github.com/unknown/repo' }
    })))

    assert_no_difference 'ExternalReview.count' do
      assert_equal false, @processor.call(event)
    end
  end

  def test_returns_false_for_non_pull_request_review_event_type
    event = build_event(event_type: 'pull_request')
    assert_equal false, @processor.call(event)
  end

  def test_returns_false_for_non_hash_payload
    event = build_event(payload: 'not-json')
    assert_equal false, @processor.call(event)
  end

  def test_returns_false_for_non_github_provider
    event = build_event(provider: 'gitlab')
    assert_equal false, @processor.call(event)
  end

  def test_handles_missing_review_data_gracefully
    payload = {
      action: 'submitted',
      pull_request: { number: 42 },
      repository: { id: 123, html_url: 'https://github.com/redmine/redmine_dev_integration' }
    }
    event = build_event(payload: JSON.generate(payload))

    assert_no_difference 'ExternalReview.count' do
      assert_equal false, @processor.call(event)
    end
  end
end
