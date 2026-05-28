# frozen_string_literal: true

class ExternalRepository < ApplicationRecord
  self.table_name = 'external_repositories'

  attr_accessor :repository_url_or_path

  belongs_to :redmine_project, class_name: 'Project'
  belongs_to :redmine_repository, class_name: 'Repository', optional: true

  validates :provider, :provider_repository_id, :owner, :repo_name, :full_name, :url, :redmine_project_id, presence: true
  validates :provider, inclusion: {in: %w[github gitlab bitbucket]}
  validates :provider_repository_id, uniqueness: {scope: :provider, case_sensitive: true}
  validates :url, format: {with: %r{\Ahttps?://\S+\z}}
  validates :full_name, format: {with: %r{\A[^/\s]+(?:/[^/\s]+)+\z}}
  validates :active, inclusion: {in: [true, false]}
  validates :webhook_registration_status, inclusion: {in: %w[not_registered registered error]}, allow_nil: true

  validate :redmine_repository_belongs_to_redmine_project

  scope :active, -> { where(active: true) }

  REGISTERED_WEBHOOK_STATUS = 'registered'
  NOT_REGISTERED_WEBHOOK_STATUS = 'not_registered'
  ERROR_WEBHOOK_STATUS = 'error'

  def webhook_registered?
    webhook_registration_status == REGISTERED_WEBHOOK_STATUS
  end

  def branch_url(branch_name)
    case provider
    when 'github'
      "#{url}/tree/#{branch_name}"
    when 'gitlab'
      "#{url}/-/tree/#{branch_name}"
    when 'bitbucket'
      "#{url}/src/#{branch_name}"
    end
  end

  private

  def redmine_repository_belongs_to_redmine_project
    return if redmine_repository_id.blank?
    return if redmine_repository.present? && redmine_repository.project_id == redmine_project_id

    errors.add(:redmine_repository_id, :invalid, message: 'must belong to the same Redmine project')
  end
end
