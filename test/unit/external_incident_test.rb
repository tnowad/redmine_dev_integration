# frozen_string_literal: true

require_relative '../test_helper'

class ExternalIncidentTest < ActiveSupport::TestCase
  fixtures :projects, :repositories

  def setup
    @project = Project.find(1)
    @external_repository = ExternalRepository.create!(
      provider: 'github',
      provider_repository_id: 'incident-test',
      owner: 'redmine',
      repo_name: 'redmine',
      full_name: 'redmine/redmine',
      url: 'https://github.com/redmine/redmine',
      redmine_project: @project
    )
  end

  def test_create_incident
    incident = ExternalIncident.create!(
      external_repository: @external_repository,
      title: 'Deployment failed: production',
      status: 'open',
      severity: 'critical',
      started_at: Time.current
    )

    assert_equal 'open', incident.status
    assert_equal 'critical', incident.severity
    assert_equal @external_repository.id, incident.external_repository_id
  end

  def test_status_validation
    incident = ExternalIncident.new(
      external_repository: @external_repository,
      title: 'Test',
      status: '',
      severity: 'medium',
      started_at: Time.current
    )
    assert_not incident.valid?
    assert incident.errors[:status].any?
  end

  def test_severity_validation
    incident = ExternalIncident.new(
      external_repository: @external_repository,
      title: 'Test',
      status: 'open',
      severity: '',
      started_at: Time.current
    )
    assert_not incident.valid?
    assert incident.errors[:severity].any?
  end

  def test_open_scope
    ExternalIncident.create!(
      external_repository: @external_repository,
      title: 'Open incident',
      status: 'open',
      severity: 'high',
      started_at: Time.current
    )
    ExternalIncident.create!(
      external_repository: @external_repository,
      title: 'Resolved incident',
      status: 'resolved',
      severity: 'high',
      started_at: Time.current,
      resolved_at: Time.current
    )

    assert_equal 1, ExternalIncident.open.count
  end

  def test_resolved_scope
    ExternalIncident.create!(
      external_repository: @external_repository,
      title: 'Open incident',
      status: 'open',
      severity: 'high',
      started_at: Time.current
    )
    ExternalIncident.create!(
      external_repository: @external_repository,
      title: 'Mitigated incident',
      status: 'mitigated',
      severity: 'high',
      started_at: Time.current
    )

    assert_equal 1, ExternalIncident.resolved.count
  end

  def test_duration_hours_when_resolved
    incident = ExternalIncident.create!(
      external_repository: @external_repository,
      title: 'Resolved incident',
      status: 'resolved',
      severity: 'high',
      started_at: 2.hours.ago,
      resolved_at: Time.current
    )

    assert_equal 2.0, incident.duration_hours
  end

  def test_duration_hours_when_mitigated
    incident = ExternalIncident.create!(
      external_repository: @external_repository,
      title: 'Mitigated incident',
      status: 'mitigated',
      severity: 'high',
      started_at: 3.hours.ago,
      mitigated_at: Time.current
    )

    assert_equal 3.0, incident.duration_hours
  end

  def test_duration_hours_without_resolved_or_mitigated
    incident = ExternalIncident.create!(
      external_repository: @external_repository,
      title: 'Open incident',
      status: 'open',
      severity: 'high',
      started_at: Time.current
    )

    assert_nil incident.duration_hours
  end

  def test_links_to_deployment
    deployment = ExternalDeployment.create!(
      provider: 'github',
      external_repository: @external_repository,
      provider_deployment_id: 'dep-1',
      environment_name: 'production',
      status: 'failed',
      completed_at: Time.current
    )

    incident = ExternalIncident.create!(
      external_repository: @external_repository,
      external_deployment: deployment,
      title: 'Failed deploy',
      status: 'open',
      severity: 'critical',
      started_at: Time.current
    )

    assert_equal deployment.id, incident.external_deployment_id
  end

  def test_links_to_issues
    issue = Issue.generate!(project: @project, subject: 'Incident issue')
    incident = ExternalIncident.create!(
      external_repository: @external_repository,
      title: 'Test incident',
      status: 'open',
      severity: 'high',
      started_at: Time.current
    )
    ExternalIncidentIssue.create!(external_incident: incident, issue: issue)

    assert_equal [issue.id], incident.issues.pluck(:id)
  end
end
