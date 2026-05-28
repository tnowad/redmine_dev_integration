# frozen_string_literal: true

require_relative '../test_helper'

class ExternalReviewTest < ActiveSupport::TestCase
  fixtures :projects, :repositories

  def setup
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
      url: 'https://github.com/redmine/redmine_dev_integration/pull/42',
      state: 'open',
      merged: false
    )

    @review = ExternalReview.new(
      provider: 'github',
      external_pull_request: @pull_request,
      provider_review_id: '1001',
      reviewer_login: 'reviewer1',
      reviewer_name: 'Reviewer One',
      state: 'APPROVED',
      body: 'LGTM',
      submitted_at: Time.current
    )
  end

  def test_valid_record
    assert_predicate @review, :valid?
  end

  def test_requires_provider
    @review.provider = nil
    assert_not_predicate @review, :valid?
    assert @review.errors[:provider].present?
  end

  def test_requires_external_pull_request
    @review.external_pull_request = nil
    assert_not_predicate @review, :valid?
    assert @review.errors[:external_pull_request].present?
  end

  def test_requires_state
    @review.state = nil
    assert_not_predicate @review, :valid?
    assert @review.errors[:state].present?
  end

  def test_enforces_uniqueness_of_provider_review_id_scoped_to_provider_and_pr
    @review.save!

    duplicate = @review.dup
    assert_not_predicate duplicate, :valid?
    assert_includes duplicate.errors[:provider_review_id], 'has already been taken'
  end

  def test_allows_same_provider_review_id_across_different_providers
    @review.save!

    @review.provider = 'gitlab'
    @review.provider_review_id = '1001'
    assert_predicate @review, :valid?
  end

  def test_approved_scope
    @review.state = 'APPROVED'
    @review.save!

    changes_requested = ExternalReview.create!(
      provider: 'github',
      external_pull_request: @pull_request,
      provider_review_id: '1002',
      reviewer_login: 'reviewer2',
      state: 'CHANGES_REQUESTED',
      submitted_at: Time.current
    )

    assert_equal 1, ExternalReview.approved.count
    assert_includes ExternalReview.approved, @review
    assert_not_includes ExternalReview.approved, changes_requested
  end

  def test_changes_requested_scope
    changes_requested = ExternalReview.create!(
      provider: 'github',
      external_pull_request: @pull_request,
      provider_review_id: '1002',
      reviewer_login: 'reviewer2',
      state: 'CHANGES_REQUESTED',
      submitted_at: Time.current
    )

    commented = ExternalReview.create!(
      provider: 'github',
      external_pull_request: @pull_request,
      provider_review_id: '1003',
      reviewer_login: 'reviewer3',
      state: 'COMMENTED',
      submitted_at: Time.current
    )

    assert_equal 1, ExternalReview.changes_requested.count
    assert_includes ExternalReview.changes_requested, changes_requested
    assert_not_includes ExternalReview.changes_requested, commented
  end

  def test_approved_predicate
    @review.state = 'APPROVED'
    assert_predicate @review, :approved?

    @review.state = 'CHANGES_REQUESTED'
    assert_not_predicate @review, :approved?
  end

  def test_changes_requested_predicate
    @review.state = 'CHANGES_REQUESTED'
    assert_predicate @review, :changes_requested?

    @review.state = 'APPROVED'
    assert_not_predicate @review, :changes_requested?
  end

  def test_belongs_to_external_pull_request
    @review.save!
    assert_equal @pull_request, @review.external_pull_request
    assert_includes @pull_request.external_reviews, @review
  end

  def test_dependent_delete_all_on_pull_request_destroy
    @review.save!
    assert_difference 'ExternalReview.count', -1 do
      @pull_request.destroy
    end
  end

  def test_review_state_on_pull_request_returns_latest
    old_review = ExternalReview.create!(
      provider: 'github',
      external_pull_request: @pull_request,
      provider_review_id: '1001',
      reviewer_login: 'reviewer1',
      state: 'CHANGES_REQUESTED',
      submitted_at: 1.day.ago
    )

    new_review = ExternalReview.create!(
      provider: 'github',
      external_pull_request: @pull_request,
      provider_review_id: '1002',
      reviewer_login: 'reviewer2',
      state: 'APPROVED',
      submitted_at: Time.current
    )

    assert_equal 'APPROVED', @pull_request.review_state
  end

  def test_approved_count_on_pull_request
    ExternalReview.create!(
      provider: 'github',
      external_pull_request: @pull_request,
      provider_review_id: '1001',
      reviewer_login: 'reviewer1',
      state: 'APPROVED',
      submitted_at: Time.current
    )

    ExternalReview.create!(
      provider: 'github',
      external_pull_request: @pull_request,
      provider_review_id: '1002',
      reviewer_login: 'reviewer2',
      state: 'APPROVED',
      submitted_at: Time.current
    )

    ExternalReview.create!(
      provider: 'github',
      external_pull_request: @pull_request,
      provider_review_id: '1003',
      reviewer_login: 'reviewer3',
      state: 'CHANGES_REQUESTED',
      submitted_at: Time.current
    )

    assert_equal 2, @pull_request.approved_count
  end

  def test_changes_requested_count_on_pull_request
    ExternalReview.create!(
      provider: 'github',
      external_pull_request: @pull_request,
      provider_review_id: '1001',
      reviewer_login: 'reviewer1',
      state: 'CHANGES_REQUESTED',
      submitted_at: Time.current
    )

    ExternalReview.create!(
      provider: 'github',
      external_pull_request: @pull_request,
      provider_review_id: '1002',
      reviewer_login: 'reviewer2',
      state: 'APPROVED',
      submitted_at: Time.current
    )

    assert_equal 1, @pull_request.changes_requested_count
  end

  def test_review_state_returns_nil_when_no_reviews
    assert_nil @pull_request.review_state
  end
end
