# frozen_string_literal: true

class ExternalPullRequest < ApplicationRecord
  STATES = %w[open closed].freeze
  SHA_FIELDS = %i[source_sha target_sha merge_commit_sha].freeze

  belongs_to :external_repository
  has_many :external_pull_request_issues, dependent: :delete_all
  has_many :issues, through: :external_pull_request_issues
  has_many :external_reviews, dependent: :delete_all

  validates :provider, :external_repository, :number, :title, :url, :state, presence: true
  validates :number, uniqueness: {scope: %i[provider external_repository_id], case_sensitive: true}
  validates :state, inclusion: {in: STATES}
  validates :merged, inclusion: {in: [true, false]}

  def sha_values
    SHA_FIELDS.filter_map { |field| public_send(field).presence }
  end

  def review_state
    latest = external_reviews.order(submitted_at: :desc).first
    latest&.state
  end

  def approved_count
    external_reviews.approved.count
  end

  def changes_requested_count
    external_reviews.changes_requested.count
  end

  def link_issues_from_texts(*texts)
    RedmineDevIntegration::IssueLinker.new.link(texts.flatten.compact).tap do |result|
      project_issue_ids = Issue.where(
        id: result.issue_ids.uniq,
        project_id: external_repository.redmine_project_id
      ).pluck(:id)

      project_issue_ids.each do |issue_id|
        ExternalPullRequestIssue.find_or_create_by!(external_pull_request_id: id, issue_id: issue_id)
      end
    end
  end
end
