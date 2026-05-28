# frozen_string_literal: true

class DevIntegrationMailer < Mailer
  # BUILD EVENTS
  def build_failed(user, build)
    @user = user
    @build = build
    @build_url = build.url
    @issues = build.issues
    redmine_headers 'Project' => build.external_repository.redmine_project.identifier
    subject = "[#{build.external_repository.redmine_project.name}] Build ##{build.build_number} FAILED - #{build.name}"
    mail to: user, subject: subject
  end

  def build_succeeded(user, build)
    @user = user
    @build = build
    @build_url = build.url
    @issues = build.issues
    redmine_headers 'Project' => build.external_repository.redmine_project.identifier
    subject = "[#{build.external_repository.redmine_project.name}] Build ##{build.build_number} SUCCEEDED - #{build.name}"
    mail to: user, subject: subject
  end

  # DEPLOYMENT EVENTS
  def deployment_succeeded(user, deployment)
    @user = user
    @deployment = deployment
    @deployment_url = deployment.environment_url
    @issues = deployment.issues
    redmine_headers 'Project' => deployment.external_repository.redmine_project.identifier
    subject = "[#{deployment.external_repository.redmine_project.name}] Deployment to #{deployment.environment_name} SUCCEEDED"
    mail to: user, subject: subject
  end

  def deployment_failed(user, deployment)
    @user = user
    @deployment = deployment
    @deployment_url = deployment.environment_url
    @issues = deployment.issues
    redmine_headers 'Project' => deployment.external_repository.redmine_project.identifier
    subject = "[#{deployment.external_repository.redmine_project.name}] Deployment to #{deployment.environment_name} FAILED"
    mail to: user, subject: subject
  end

  # PR EVENTS
  def pr_opened(user, pull_request)
    @user = user
    @pull_request = pull_request
    @pr_url = pull_request.url
    @issues = pull_request.issues
    redmine_headers 'Project' => pull_request.external_repository.redmine_project.identifier
    subject = "[#{pull_request.external_repository.redmine_project.name}] PR ##{pull_request.number} opened - #{pull_request.title}"
    mail to: user, subject: subject
  end

  def pr_reviewed(user, pull_request, review_state)
    @user = user
    @pull_request = pull_request
    @pr_url = pull_request.url
    @review_state = review_state
    @issues = pull_request.issues
    redmine_headers 'Project' => pull_request.external_repository.redmine_project.identifier
    subject = "[#{pull_request.external_repository.redmine_project.name}] PR ##{pull_request.number} #{review_state} - #{pull_request.title}"
    mail to: user, subject: subject
  end

  # INCIDENT EVENTS
  def incident_created(user, incident)
    @user = user
    @incident = incident
    @issues = incident.issues
    redmine_headers 'Project' => incident.external_repository.redmine_project.identifier
    subject = "[#{incident.external_repository.redmine_project.name}] Incident: #{incident.title}"
    mail to: user, subject: subject
  end

  # CLASS METHODS for recipient collection + async delivery
  def self.deliver_build_failed(build)
    return unless Setting.notified_events.include?('build_failed')

    users = build_recipients(build)
    users.each { |u| build_failed(u, build).deliver_later }
  end

  def self.deliver_build_succeeded(build)
    return unless Setting.notified_events.include?('build_succeeded')

    users = build_recipients(build)
    users.each { |u| build_succeeded(u, build).deliver_later }
  end

  def self.deliver_deployment_succeeded(deployment)
    return unless Setting.notified_events.include?('deployment_succeeded')

    users = deployment_recipients(deployment)
    users.each { |u| deployment_succeeded(u, deployment).deliver_later }
  end

  def self.deliver_deployment_failed(deployment)
    return unless Setting.notified_events.include?('deployment_failed')

    users = deployment_recipients(deployment)
    users.each { |u| deployment_failed(u, deployment).deliver_later }
  end

  def self.deliver_pr_opened(pr)
    return unless Setting.notified_events.include?('pr_opened')

    users = pr_recipients(pr)
    users.each { |u| pr_opened(u, pr).deliver_later }
  end

  def self.deliver_pr_reviewed(pr, review_state)
    return unless Setting.notified_events.include?('pr_reviewed')

    users = pr_recipients(pr)
    users.each { |u| pr_reviewed(u, pr, review_state).deliver_later }
  end

  def self.deliver_incident_created(incident)
    return unless Setting.notified_events.include?('incident_created')

    users = incident_recipients(incident)
    users.each { |u| incident_created(u, incident).deliver_later }
  end

  private_class_method

  def self.build_recipients(build)
    build.issues.flat_map(&:notified_users).uniq.select { |u| u.active? && u.mail.present? }
  end

  def self.deployment_recipients(deployment)
    deployment.issues.flat_map(&:notified_users).uniq.select { |u| u.active? && u.mail.present? }
  end

  def self.pr_recipients(pr)
    pr.issues.flat_map(&:notified_users).uniq.select { |u| u.active? && u.mail.present? }
  end

  def self.incident_recipients(incident)
    incident.issues.flat_map(&:notified_users).uniq.select { |u| u.active? && u.mail.present? }
  end
end
