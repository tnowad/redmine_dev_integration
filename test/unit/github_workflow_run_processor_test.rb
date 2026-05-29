# frozen_string_literal: true

require_relative '../test_helper'

class GithubWorkflowRunProcessorTest < ActiveSupport::TestCase
  fixtures :projects, :repositories

  def setup
    @processor = RedmineDevIntegration::GithubWorkflowRunProcessor.new
    @external_repository = ExternalRepository.create!(
      provider: 'github',
      provider_repository_id: '123',
      owner: 'redmine',
      repo_name: 'redmine_dev_integration',
      full_name: 'redmine/redmine_dev_integration',
      url: 'https://github.com/redmine/redmine_dev_integration',
      redmine_project: projects(:projects_001),
      redmine_repository: nil
    )
  end

  def build_event(attributes = {})
    ExternalProviderEvent.new({
      provider: 'github',
      delivery_id: "delivery-#{SecureRandom.hex(4)}",
      event_type: 'workflow_run',
      payload: JSON.generate({
        repository: {
          id: 123,
          html_url: 'https://github.com/redmine/redmine_dev_integration'
        },
        workflow_run: {
          id: 101,
          run_number: 42,
          display_title: 'CI build',
          name: 'CI',
          status: 'queued',
          conclusion: nil,
          html_url: 'https://github.com/redmine/redmine_dev_integration/actions/runs/101',
          head_sha: 'abc123',
          head_branch: 'main',
          actor: {login: 'contributor'},
          run_started_at: '2026-05-25T10:00:00Z',
          created_at: '2026-05-25T10:00:00Z',
          updated_at: '2026-05-25T11:00:00Z',
          head_commit: {message: 'Initial commit'}
        }
      }),
      status: 'pending'
    }.merge(attributes))
  end

  def test_workflow_run_creates_build_and_links_issues
    project = Project.generate!(issue_key_prefix: 'AUTH')
    issue = Issue.generate!(project: project, subject: 'Login fix')
    @external_repository.update!(redmine_project: project)

    event = build_event(payload: JSON.generate({
      repository: {
        id: 123,
        html_url: 'https://github.com/redmine/redmine_dev_integration'
      },
      workflow_run: {
        id: 101,
        run_number: 42,
        display_title: "CI build for #{issue.issue_key}",
        name: 'CI',
        status: 'completed',
        conclusion: 'success',
        html_url: 'https://github.com/redmine/redmine_dev_integration/actions/runs/101',
        head_sha: 'abc123',
        head_branch: "feature/#{issue.issue_key}-login",
        actor: {login: 'contributor'},
        run_started_at: '2026-05-25T10:00:00Z',
        created_at: '2026-05-25T10:00:00Z',
        updated_at: '2026-05-25T11:00:00Z',
        head_commit: {message: "Fix #{issue.issue_key}"}
      }
    }))

    assert @processor.call(event)

    build = ExternalBuild.find_by!(provider: 'github', external_repository: @external_repository, provider_build_id: '101')
    assert_equal 42, build.build_number
    assert_equal "CI build for #{issue.issue_key}", build.name
    assert_equal 'success', build.status
    assert_equal 'success', build.conclusion
    assert_equal 'https://github.com/redmine/redmine_dev_integration/actions/runs/101', build.url
    assert_equal 'abc123', build.sha
    assert_equal "feature/#{issue.issue_key}-login", build.ref
    assert_equal "feature/#{issue.issue_key}-login", build.branch_name
    assert_equal 'contributor', build.author_login
    assert_equal Time.zone.parse('2026-05-25T10:00:00Z'), build.started_at
    assert_equal Time.zone.parse('2026-05-25T11:00:00Z'), build.finished_at
    assert_equal Time.zone.parse('2026-05-25T11:00:00Z'), build.last_event_at
    assert_equal [issue.id], build.issues.pluck(:id)
    assert_equal 1, build.external_build_issues.count
  end

  def test_workflow_run_updates_existing_build_without_duplication
    first_event = build_event(payload: JSON.generate({
      repository: {
        id: 123,
        html_url: 'https://github.com/redmine/redmine_dev_integration'
      },
      workflow_run: {
        id: 101,
        run_number: 42,
        display_title: 'CI build',
        name: 'CI',
        status: 'queued',
        conclusion: nil,
        html_url: 'https://github.com/redmine/redmine_dev_integration/actions/runs/101',
        head_sha: 'abc123',
        head_branch: 'main',
        actor: {login: 'contributor'},
        run_started_at: '2026-05-25T10:00:00Z',
        created_at: '2026-05-25T10:00:00Z',
        updated_at: '2026-05-25T10:00:00Z'
      }
    }))

    second_event = build_event(payload: JSON.generate({
      repository: {
        id: 123,
        html_url: 'https://github.com/redmine/redmine_dev_integration'
      },
      workflow_run: {
        id: 101,
        run_number: 42,
        display_title: 'CI build',
        name: 'CI',
        status: 'completed',
        conclusion: 'failure',
        html_url: 'https://github.com/redmine/redmine_dev_integration/actions/runs/101',
        head_sha: 'def456',
        head_branch: 'main',
        actor: {login: 'contributor'},
        run_started_at: '2026-05-25T10:00:00Z',
        created_at: '2026-05-25T10:00:00Z',
        updated_at: '2026-05-25T12:00:00Z'
      }
    }))

    assert @processor.call(first_event)
    assert @processor.call(second_event)

    assert_equal 1, ExternalBuild.where(provider: 'github', external_repository: @external_repository, provider_build_id: '101').count

    build = ExternalBuild.find_by!(provider: 'github', external_repository: @external_repository, provider_build_id: '101')
    assert_equal 'failed', build.status
    assert_equal 'failure', build.conclusion
    assert_equal 'def456', build.sha
    assert_equal Time.zone.parse('2026-05-25T12:00:00Z'), build.finished_at
    assert_equal Time.zone.parse('2026-05-25T12:00:00Z'), build.last_event_at
  end

  def test_missing_repository_is_ignored_without_error
    event = build_event(payload: JSON.generate({
      repository: {
        id: 999,
        html_url: 'https://github.com/other/repo'
      },
      workflow_run: {
        id: 101,
        run_number: 42,
        display_title: 'CI build',
        name: 'CI',
        status: 'completed',
        conclusion: 'success',
        html_url: 'https://github.com/other/repo/actions/runs/101',
        head_sha: 'abc123',
        head_branch: 'main',
        actor: {login: 'contributor'},
        run_started_at: '2026-05-25T10:00:00Z',
        created_at: '2026-05-25T10:00:00Z',
        updated_at: '2026-05-25T11:00:00Z',
        head_commit: {message: 'Fix AUTH-9999'}
      }
    }))

    refute @processor.call(event)
    assert_nil ExternalBuild.find_by(provider: 'github', provider_build_id: '101')
  end

  def test_workflow_run_links_to_onboarded_repository_without_redmine_repository
    @external_repository.update!(redmine_repository: nil)

    event = build_event(payload: JSON.generate({
      repository: {
        id: 123,
        html_url: 'https://github.com/redmine/redmine_dev_integration'
      },
      workflow_run: {
        id: 103,
        run_number: 44,
        display_title: 'CI build',
        name: 'CI',
        status: 'completed',
        conclusion: 'success',
        html_url: 'https://github.com/redmine/redmine_dev_integration/actions/runs/103',
        head_sha: 'abc123',
        head_branch: 'main',
        actor: {login: 'contributor'},
        run_started_at: '2026-05-25T10:00:00Z',
        created_at: '2026-05-25T10:00:00Z',
        updated_at: '2026-05-25T11:00:00Z',
        head_commit: {message: 'Fix AUTH-9999'}
      }
    }))

    assert @processor.call(event)

    build = ExternalBuild.find_by!(provider: 'github', external_repository: @external_repository, provider_build_id: '103')
    assert_equal 44, build.build_number
  end

  def test_inactive_repository_does_not_create_build
    @external_repository.update!(active: false)

    event = build_event(payload: JSON.generate({
      repository: {
        id: 123,
        html_url: 'https://github.com/redmine/redmine_dev_integration'
      },
      workflow_run: {
        id: 104,
        run_number: 45,
        display_title: 'CI build',
        name: 'CI',
        status: 'completed',
        conclusion: 'success',
        html_url: 'https://github.com/redmine/redmine_dev_integration/actions/runs/104',
        head_sha: 'abc123',
        head_branch: 'main',
        actor: {login: 'contributor'},
        run_started_at: '2026-05-25T10:00:00Z',
        created_at: '2026-05-25T10:00:00Z',
        updated_at: '2026-05-25T11:00:00Z',
        head_commit: {message: 'Fix AUTH-9999'}
      }
    }))

    refute @processor.call(event)
    assert_nil ExternalBuild.find_by(provider: 'github', provider_build_id: '104')
  end

  def test_unknown_issue_key_does_not_fail_processing
    @external_repository.update!(redmine_project: projects(:projects_001))

    event = build_event(payload: JSON.generate({
      repository: {
        id: 123,
        html_url: 'https://github.com/redmine/redmine_dev_integration'
      },
      workflow_run: {
        id: 102,
        run_number: 43,
        display_title: 'CI build',
        name: 'CI',
        status: 'completed',
        conclusion: 'success',
        html_url: 'https://github.com/redmine/redmine_dev_integration/actions/runs/102',
        head_sha: 'abc123',
        head_branch: 'main',
        actor: {login: 'contributor'},
        run_started_at: '2026-05-25T10:00:00Z',
        created_at: '2026-05-25T10:00:00Z',
        updated_at: '2026-05-25T11:00:00Z',
        head_commit: {message: 'Fix AUTH-9999'}
      }
    }))

    assert_nothing_raised do
      assert @processor.call(event)
    end

    build = ExternalBuild.find_by!(provider: 'github', external_repository: @external_repository, provider_build_id: '102')
    assert_empty build.issues
  end

  def test_workflow_run_links_issue_via_sha_when_text_matching_finds_none
    project = Project.generate!(issue_key_prefix: 'AUTH')
    issue = Issue.generate!(project: project, subject: 'Trace target')
    @external_repository.update!(redmine_project: project)

    pull_request = ExternalPullRequest.create!(
      provider: 'github',
      external_repository: @external_repository,
      number: 11,
      title: 'Trace PR',
      url: 'https://github.com/redmine/redmine_dev_integration/pull/11',
      state: 'open',
      merged: false,
      source_sha: 'abc123'
    )
    ExternalPullRequestIssue.create!(external_pull_request: pull_request, issue: issue)

    event = build_event(payload: JSON.generate({
      repository: {
        id: 123,
        html_url: 'https://github.com/redmine/redmine_dev_integration'
      },
      workflow_run: {
        id: 201,
        run_number: 50,
        display_title: 'CI build',
        name: 'CI',
        status: 'completed',
        conclusion: 'success',
        html_url: 'https://github.com/redmine/redmine_dev_integration/actions/runs/201',
        head_sha: 'abc123',
        head_branch: 'main',
        actor: {login: 'contributor'},
        run_started_at: '2026-05-25T10:00:00Z',
        created_at: '2026-05-25T10:00:00Z',
        updated_at: '2026-05-25T11:00:00Z',
        head_commit: {message: 'Refactor internal wiring'}
      }
    }))

    assert @processor.call(event)

    build = ExternalBuild.find_by!(provider: 'github', external_repository: @external_repository, provider_build_id: '201')
    assert_equal [issue.id], build.issues.pluck(:id)
    assert_equal 1, build.external_build_issues.count
  end
end
