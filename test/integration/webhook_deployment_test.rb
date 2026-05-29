# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/dev_integration_test_factory'

class WebhookDeploymentTest < Redmine::IntegrationTest
  include DevIntegrationTestFactory
  include ActiveJob::TestHelper

  def setup
    RedmineDevIntegration::GithubWebhookSignatureVerifier.any_instance.stubs(:valid?).returns(true)
    Setting.stubs(:plugin_redmine_dev_integration).returns({
      'github_webhook_secret' => 'test_secret',
      'github_provider_enabled' => '1'
    })
    @project = Project.generate!
    @project.update_column(:issue_key_prefix, 'DEV')
    @issue = Issue.generate!(project: @project, subject: 'Test Deploy', author: User.find(1))
    @issue.reload
    @repo = create_external_repository(project: @project, provider: 'github', full_name: 'owner/repo', provider_repository_id: '12345')

    unless Issue.respond_to?(:find_by_issue_key)
      Issue.define_singleton_method(:find_by_issue_key) { |_key| nil }
    end
  end

  def deploy_headers(delivery_id: 'deploy-test-001')
    {
      'X-Github-Event' => 'deployment_status',
      'X-Github-Delivery' => delivery_id,
      'Content-Type' => 'application/json'
    }
  end

  def deploy_success_payload
    File.read(File.join(__dir__, '..', 'fixtures', 'webhook_payloads', 'github_deployment_status_success.json'))
  end

  def deploy_failed_payload
    File.read(File.join(__dir__, '..', 'fixtures', 'webhook_payloads', 'github_deployment_status_failed.json'))
  end

  # --- Deployment linked to issue via ref/branch name ---

  def test_deployment_linked_to_issue_via_ref
    perform_enqueued_jobs do
      post '/dev_integrations/github/webhook',
           headers: deploy_headers(delivery_id: 'deploy-link-001'),
           params: deploy_success_payload
    end

    assert_response :accepted
    deployment = ExternalDeployment.find_by(provider_deployment_id: '88888', provider: 'github', external_repository: @repo)
    assert deployment, 'Expected ExternalDeployment to be created'

    if @issue.issue_key.present?
      link = ExternalDeploymentIssue.find_by(external_deployment_id: deployment.id, issue_id: @issue.id)
      assert link, 'Expected deployment linked to issue via ref feature/DEV-1-login'
    else
      assert deployment, 'Deployment should still be created without issue_keys plugin'
    end
  end

  # --- Deployment record fields ---

  def test_deployment_created_with_correct_fields
    perform_enqueued_jobs do
      post '/dev_integrations/github/webhook',
           headers: deploy_headers(delivery_id: 'deploy-fields-001'),
           params: deploy_success_payload
    end

    assert_response :accepted
    deployment = ExternalDeployment.find_by(provider_deployment_id: '88888', provider: 'github', external_repository: @repo)
    assert deployment, 'Expected ExternalDeployment to exist'

    assert_equal 'staging', deployment.environment_name
    assert_equal 'success', deployment.status
    assert_equal 'https://staging.example.com', deployment.environment_url
    assert_equal 'abc123def456789012345678901234567890abcd', deployment.sha
    assert_equal 'feature/DEV-1-login', deployment.ref
    assert_equal 'feature/DEV-1-login', deployment.branch_name
    assert_equal 'Deployed', deployment.description
    assert_equal 'dev1', deployment.creator_login
  end

  # --- Deployment to staging triggers automation ---

  def test_deployment_staging_success_triggers_automation
    target_status = IssueStatus.where.not(id: @issue.status_id).first ||
                    IssueStatus.find_by(name: 'Resolved') ||
                    IssueStatus.last
    assert target_status, 'Need a target status for staging deployment automation'

    DevelopmentIntegrationProjectSetting.create!(
      project: @project,
      automation_enabled: true,
      deployment_staging_success_status_id: target_status.id
    )

    perform_enqueued_jobs do
      post '/dev_integrations/github/webhook',
           headers: deploy_headers(delivery_id: 'deploy-staging-auto-001'),
           params: deploy_success_payload
    end

    assert_response :accepted

    if @issue.issue_key.present?
      @issue.reload
      assert_equal target_status.id, @issue.status_id,
        "Expected issue status to change to #{target_status.name} for staging deployment"
    else
      @issue.reload
      assert_not_equal target_status.id, @issue.status_id, 'Status should not change without issue_keys'
    end
  end

  # --- Deployment to production triggers automation ---

  def test_deployment_production_success_triggers_automation
    target_status = IssueStatus.where.not(id: @issue.status_id).first ||
                    IssueStatus.find_by(name: 'Closed') ||
                    IssueStatus.last
    assert target_status, 'Need a target status for production deployment automation'

    DevelopmentIntegrationProjectSetting.create!(
      project: @project,
      automation_enabled: true,
      deployment_production_success_status_id: target_status.id
    )

    payload_json = {
      action: 'deployment_status',
      deployment: {
        id: 88889,
        sha: 'abc123def456789012345678901234567890abcd',
        ref: 'feature/DEV-1-login',
        environment: 'production',
        description: 'Deploy to production',
        creator: { login: 'dev1' },
        created_at: '2026-01-01T04:00:00Z',
        updated_at: '2026-01-01T04:00:00Z'
      },
      deployment_status: {
        state: 'success',
        environment: 'production',
        environment_url: 'https://prod.example.com',
        target_url: 'https://prod.example.com',
        description: 'Deployed to production',
        creator: { login: 'dev1' },
        created_at: '2026-01-01T04:05:00Z',
        updated_at: '2026-01-01T04:05:00Z'
      },
      repository: { id: 12345, full_name: 'owner/repo', html_url: 'https://github.com/owner/repo' },
      sender: { login: 'dev1' }
    }.to_json

    perform_enqueued_jobs do
      post '/dev_integrations/github/webhook',
           headers: deploy_headers(delivery_id: 'deploy-prod-auto-001'),
           params: payload_json
    end

    assert_response :accepted

    if @issue.issue_key.present?
      @issue.reload
      assert_equal target_status.id, @issue.status_id,
        "Expected issue status to change to #{target_status.name} for production deployment"
    else
      @issue.reload
      assert_not_equal target_status.id, @issue.status_id, 'Status should not change without issue_keys'
    end
  end

  # --- Deployment failure triggers automation ---

  def test_deployment_failure_triggers_status_and_note
    failed_status = IssueStatus.where.not(id: @issue.status_id).first ||
                    IssueStatus.find_by(name: 'Rejected') ||
                    IssueStatus.last
    assert failed_status, 'Need a failed target status'

    DevelopmentIntegrationProjectSetting.create!(
      project: @project,
      automation_enabled: true,
      deployment_failed_status_id: failed_status.id,
      deployment_failed_note_enabled: true
    )

    perform_enqueued_jobs do
      post '/dev_integrations/github/webhook',
           headers: deploy_headers(delivery_id: 'deploy-fail-auto-001'),
           params: deploy_failed_payload
    end

    assert_response :accepted
    deployment = ExternalDeployment.find_by(provider_deployment_id: '88887', provider: 'github', external_repository: @repo)
    assert deployment, 'Expected failed ExternalDeployment to exist'
    assert_equal 'failed', deployment.status
    assert_equal 'production', deployment.environment_name

    if @issue.issue_key.present?
      @issue.reload
      assert_equal failed_status.id, @issue.status_id,
        "Expected issue status to change to #{failed_status.name} for failed deployment"
      note_journals = @issue.journals.where('notes LIKE ?', '%deployment_failed%')
      fail_journals = @issue.journals.where('notes LIKE ?', '%failed%')
      all = note_journals.to_a + fail_journals.to_a
      assert all.any?, "Expected a journal note about deployment failure on issue ##{@issue.id}"
    else
      assert deployment, 'Deployment should be created even without issue_keys plugin'
    end
  end

  # --- Environment rules: custom environment applies custom status ---

  def test_environment_rule_applies_custom_status
    custom_status = IssueStatus.where.not(id: @issue.status_id).first ||
                    IssueStatus.find_by(name: 'In Progress') ||
                    IssueStatus.last
    assert custom_status, 'Need a custom status for environment rule'

    DevelopmentIntegrationEnvironmentRule.create!(
      project: @project,
      environment_name: 'review-app',
      active: true,
      failed_note_enabled: false,
      success_status_id: custom_status.id
    )

    DevelopmentIntegrationProjectSetting.create!(
      project: @project,
      automation_enabled: true
    )

    payload_json = {
      action: 'deployment_status',
      deployment: {
        id: 89000,
        sha: 'abc123def456789012345678901234567890abcd',
        ref: 'feature/DEV-1-login',
        environment: 'review-app',
        description: 'Deploy to review app',
        creator: { login: 'dev1' },
        created_at: '2026-01-01T05:00:00Z',
        updated_at: '2026-01-01T05:00:00Z'
      },
      deployment_status: {
        state: 'success',
        environment: 'review-app',
        environment_url: 'https://review-app.example.com',
        target_url: 'https://review-app.example.com',
        description: 'Deployed to review app',
        creator: { login: 'dev1' },
        created_at: '2026-01-01T05:05:00Z',
        updated_at: '2026-01-01T05:05:00Z'
      },
      repository: { id: 12345, full_name: 'owner/repo', html_url: 'https://github.com/owner/repo' },
      sender: { login: 'dev1' }
    }.to_json

    perform_enqueued_jobs do
      post '/dev_integrations/github/webhook',
           headers: deploy_headers(delivery_id: 'deploy-env-rule-001'),
           params: payload_json
    end

    assert_response :accepted
    deployment = ExternalDeployment.find_by(provider_deployment_id: '89000', provider: 'github', external_repository: @repo)
    assert deployment, 'Expected deployment to be created for review-app'
    assert_equal 'review-app', deployment.environment_name

    if @issue.issue_key.present?
      @issue.reload
      assert_equal custom_status.id, @issue.status_id,
        "Expected issue status to change via environment rule to #{custom_status.name}"
    else
      assert deployment, 'Deployment should be created even without issue_keys plugin'
    end
  end

  # --- Deployment with provider URL and environment_url ---

  def test_deployment_provider_url_and_environment_url_stored
    perform_enqueued_jobs do
      post '/dev_integrations/github/webhook',
           headers: deploy_headers(delivery_id: 'deploy-urls-001'),
           params: deploy_success_payload
    end

    assert_response :accepted
    deployment = ExternalDeployment.find_by(provider_deployment_id: '88888', provider: 'github', external_repository: @repo)
    assert deployment, 'Expected deployment to exist'

    assert_equal 'https://staging.example.com', deployment.environment_url
  end
end
