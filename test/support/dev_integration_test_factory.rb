# frozen_string_literal: true

module DevIntegrationTestFactory
  def create_project_with_prefix(name: 'test', prefix: 'DEV')
    project = Project.generate!(identifier: name)
    project.update_column(:issue_key_prefix, prefix) if prefix
    project.reload
  end

  def create_issue_with_key(project:, tracker: nil, subject: 'Test issue for E2E')
    tracker ||= Tracker.first || Tracker.generate!(name: 'Bug')
    issue = Issue.generate!(
      project: project,
      tracker: tracker,
      subject: subject,
      author: User.find(1)
    )
    issue.reload
  end

  def create_external_repository(project:, provider: 'github', full_name: 'owner/repo', provider_repository_id: '12345')
    ExternalRepository.create!(
      redmine_project: project,
      provider: provider,
      provider_repository_id: provider_repository_id,
      owner: full_name.split('/').first,
      repo_name: full_name.split('/').last,
      full_name: full_name,
      url: "https://#{provider}.com/#{full_name}",
      active: true
    )
  end

  def create_dev_panel_data(issue:, repository:)
    branch = ExternalBranch.create!(
      external_repository: repository,
      name: "feature/#{issue.issue_key.presence || issue.id}-login",
      url: "https://github.com/#{repository.full_name}/tree/feature/#{issue.issue_key.presence || issue.id}-login",
      sha: 'abc123def456789',
      state: 'active'
    )
    branch.issues << issue

    pr = ExternalPullRequest.create!(
      provider: repository.provider,
      external_repository: repository,
      number: 42,
      title: "Fix #{issue.issue_key.presence || "##{issue.id}"} add login",
      body: 'Implementation of login feature',
      url: "https://github.com/#{repository.full_name}/pull/42",
      state: 'open',
      author_login: 'dev1',
      source_branch: "feature/#{issue.issue_key.presence || issue.id}-login",
      target_branch: 'main',
      source_sha: 'abc123def456789',
      target_sha: 'base999base999',
      merged: false,
      opened_at: 2.days.ago,
      last_event_at: 1.day.ago
    )
    pr.issues << issue

    build = ExternalBuild.create!(
      provider: repository.provider,
      external_repository: repository,
      provider_build_id: 'run-99999',
      build_number: 99,
      name: 'CI Build',
      status: 'success',
      conclusion: 'success',
      url: "https://github.com/#{repository.full_name}/actions/runs/99",
      sha: 'abc123def456789',
      ref: "feature/#{issue.issue_key.presence || issue.id}-login",
      branch_name: "feature/#{issue.issue_key.presence || issue.id}-login",
      author_login: 'dev1',
      started_at: 1.day.ago,
      finished_at: 1.day.ago + 5.minutes,
      last_event_at: 1.day.ago + 5.minutes
    )
    build.issues << issue

    deployment = ExternalDeployment.create!(
      provider: repository.provider,
      external_repository: repository,
      provider_deployment_id: 'deploy-88888',
      environment_name: 'staging',
      environment_url: 'https://staging.example.com',
      status: 'success',
      sha: 'abc123def456789',
      ref: "feature/#{issue.issue_key.presence || issue.id}-login",
      branch_name: "feature/#{issue.issue_key.presence || issue.id}-login",
      description: 'Deployed feature branch',
      creator_login: 'dev1',
      started_at: 1.day.ago + 5.minutes,
      completed_at: 1.day.ago + 10.minutes,
      last_event_at: 1.day.ago + 10.minutes
    )
    deployment.issues << issue

    { branch: branch, pull_request: pr, build: build, deployment: deployment }
  end

  def enable_automation(project:, **status_mappings)
    setting = DevelopmentIntegrationProjectSetting.for_project(project)
    setting.assign_attributes(
      automation_enabled: true,
      show_dev_panel: true,
      show_builds: true,
      show_deployments: true
    )
    setting.assign_attributes(status_mappings) if status_mappings.any?
    setting.save!
    setting
  end

  def fixture_payload(name)
    path = File.join(__dir__, '..', 'fixtures', 'webhook_payloads', "#{name}.json")
    JSON.parse(File.read(path))
  end
end
