# frozen_string_literal: true

require_relative '../test_helper'

class GitlabPipelineProcessorTest < ActiveSupport::TestCase
  fixtures :projects, :repositories

  def setup
    @processor = RedmineDevIntegration::GitlabPipelineProcessor.new
    @external_repository = ExternalRepository.create!(
      provider: 'gitlab',
      provider_repository_id: '456',
      owner: 'redmine',
      repo_name: 'redmine_dev_integration',
      full_name: 'redmine/redmine_dev_integration',
      url: 'https://gitlab.example.com/redmine/redmine_dev_integration',
      redmine_project: projects(:projects_001),
      redmine_repository: nil
    )
  end

  def build_event(attributes = {})
    ExternalProviderEvent.new({
      provider: 'gitlab',
      delivery_id: "delivery-#{SecureRandom.hex(4)}",
      event_type: 'Pipeline Hook',
      payload: JSON.generate({
        object_attributes: {
          id: 101,
          iid: 42,
          name: 'Pipeline',
          status: 'created',
          url: 'https://gitlab.example.com/redmine/redmine_dev_integration/-/pipelines/101',
          sha: 'abc123',
          ref: 'main',
          created_at: '2026-05-25T10:00:00Z',
          finished_at: nil,
          updated_at: '2026-05-25T10:05:00Z'
        },
        project: {
          id: 456,
          web_url: 'https://gitlab.example.com/redmine/redmine_dev_integration'
        },
        user: {
          username: 'contributor',
          name: 'Contributor'
        },
        commit: {
          message: 'Initial commit',
          title: 'Initial commit title'
        }
      }),
      status: 'pending'
    }.merge(attributes))
  end

  def test_pipeline_hook_creates_build_and_links_issues
    project = Project.generate!(issue_key_prefix: 'AUTH')
    issue = Issue.generate!(project: project, subject: 'Login fix')
    @external_repository.update!(redmine_project: project)

    event = build_event(payload: JSON.generate({
      object_attributes: {
        id: 101,
        iid: 42,
        name: "Pipeline for #{issue.issue_key}",
        status: 'success',
        url: 'https://gitlab.example.com/redmine/redmine_dev_integration/-/pipelines/101',
        sha: 'abc123',
        ref: "feature/#{issue.issue_key}-login",
        created_at: '2026-05-25T10:00:00Z',
        finished_at: '2026-05-25T10:30:00Z',
        updated_at: '2026-05-25T10:35:00Z'
      },
      project: {
        id: 456,
        web_url: 'https://gitlab.example.com/redmine/redmine_dev_integration'
      },
      user: {
        username: 'contributor',
        name: 'Contributor'
      },
      commit: {
        message: "Fix #{issue.issue_key}",
        title: "Pipeline #{issue.issue_key}"
      }
    }))

    assert @processor.call(event)

    build = ExternalBuild.find_by!(
      provider: 'gitlab',
      external_repository: @external_repository,
      provider_build_id: '101'
    )

    assert_equal 42, build.build_number
    assert_equal "Pipeline for #{issue.issue_key}", build.name
    assert_equal 'success', build.status
    assert_equal 'success', build.conclusion
    assert_equal 'https://gitlab.example.com/redmine/redmine_dev_integration/-/pipelines/101', build.url
    assert_equal 'abc123', build.sha
    assert_equal "feature/#{issue.issue_key}-login", build.ref
    assert_equal "feature/#{issue.issue_key}-login", build.branch_name
    assert_equal 'contributor', build.author_login
    assert_equal Time.zone.parse('2026-05-25T10:00:00Z'), build.started_at
    assert_equal Time.zone.parse('2026-05-25T10:30:00Z'), build.finished_at
    assert_equal Time.zone.parse('2026-05-25T10:35:00Z'), build.last_event_at
    assert_equal [issue.id], build.issues.pluck(:id)
    assert_equal 1, build.external_build_issues.count
  end

  def test_pipeline_hook_updates_existing_build_without_duplication
    first_event = build_event(payload: JSON.generate({
      object_attributes: {
        id: 101,
        iid: 42,
        name: 'Pipeline',
        status: 'created',
        url: 'https://gitlab.example.com/redmine/redmine_dev_integration/-/pipelines/101',
        sha: 'abc123',
        ref: 'main',
        created_at: '2026-05-25T10:00:00Z',
        updated_at: '2026-05-25T10:05:00Z'
      },
      project: {
        id: 456,
        web_url: 'https://gitlab.example.com/redmine/redmine_dev_integration'
      },
      user: {
        username: 'contributor',
        name: 'Contributor'
      },
      commit: {
        message: 'Initial commit',
        title: 'Initial commit title'
      }
    }))

    second_event = build_event(payload: JSON.generate({
      object_attributes: {
        id: 101,
        iid: 42,
        name: 'Pipeline',
        status: 'running',
        url: 'https://gitlab.example.com/redmine/redmine_dev_integration/-/pipelines/101',
        sha: 'def456',
        ref: 'main',
        created_at: '2026-05-25T10:00:00Z',
        updated_at: '2026-05-25T11:00:00Z'
      },
      project: {
        id: 456,
        web_url: 'https://gitlab.example.com/redmine/redmine_dev_integration'
      },
      user: {
        username: 'contributor',
        name: 'Contributor'
      },
      commit: {
        message: 'Initial commit',
        title: 'Initial commit title'
      }
    }))

    assert @processor.call(first_event)
    assert @processor.call(second_event)

    assert_equal 1, ExternalBuild.where(provider: 'gitlab', external_repository: @external_repository, provider_build_id: '101').count

    build = ExternalBuild.find_by!(provider: 'gitlab', external_repository: @external_repository, provider_build_id: '101')
    assert_equal 'in_progress', build.status
    assert_equal 'def456', build.sha
    assert_equal Time.zone.parse('2026-05-25T11:00:00Z'), build.last_event_at
  end

  def test_missing_repository_is_ignored_without_error
    event = build_event(payload: JSON.generate({
      object_attributes: {
        id: 101,
        iid: 42,
        name: 'Pipeline',
        status: 'success',
        url: 'https://gitlab.example.com/other/repo/-/pipelines/101',
        sha: 'abc123',
        ref: 'main',
        created_at: '2026-05-25T10:00:00Z',
        updated_at: '2026-05-25T10:05:00Z'
      },
      project: {
        id: 999,
        web_url: 'https://gitlab.example.com/other/repo'
      },
      user: {
        username: 'contributor',
        name: 'Contributor'
      },
      commit: {
        message: 'Fix AUTH-9999',
        title: 'Pipeline'
      }
    }))

    refute @processor.call(event)
    assert_nil ExternalBuild.find_by(provider: 'gitlab', provider_build_id: '101')
  end

  def test_pipeline_hook_links_to_onboarded_repository_without_redmine_repository
    @external_repository.update!(redmine_repository: nil)

    event = build_event(payload: JSON.generate({
      object_attributes: {
        id: 103,
        iid: 44,
        name: 'Pipeline',
        status: 'success',
        url: 'https://gitlab.example.com/redmine/redmine_dev_integration/-/pipelines/103',
        sha: 'abc123',
        ref: 'main',
        created_at: '2026-05-25T10:00:00Z',
        updated_at: '2026-05-25T10:35:00Z'
      },
      project: {
        id: 456,
        web_url: 'https://gitlab.example.com/redmine/redmine_dev_integration'
      },
      user: {
        username: 'contributor',
        name: 'Contributor'
      },
      commit: {
        message: 'Fix AUTH-9999',
        title: 'Pipeline AUTH-9999'
      }
    }))

    assert @processor.call(event)

    build = ExternalBuild.find_by!(provider: 'gitlab', external_repository: @external_repository, provider_build_id: '103')
    assert_equal 44, build.build_number
  end

  def test_inactive_repository_does_not_create_build
    @external_repository.update!(active: false)

    event = build_event(payload: JSON.generate({
      object_attributes: {
        id: 104,
        iid: 45,
        name: 'Pipeline',
        status: 'success',
        url: 'https://gitlab.example.com/redmine/redmine_dev_integration/-/pipelines/104',
        sha: 'abc123',
        ref: 'main',
        created_at: '2026-05-25T10:00:00Z',
        updated_at: '2026-05-25T10:35:00Z'
      },
      project: {
        id: 456,
        web_url: 'https://gitlab.example.com/redmine/redmine_dev_integration'
      },
      user: {
        username: 'contributor',
        name: 'Contributor'
      },
      commit: {
        message: 'Fix AUTH-9999',
        title: 'Pipeline AUTH-9999'
      }
    }))

    refute @processor.call(event)
    assert_nil ExternalBuild.find_by(provider: 'gitlab', provider_build_id: '104')
  end

  def test_unknown_issue_key_does_not_fail_processing
    event = build_event(payload: JSON.generate({
      object_attributes: {
        id: 102,
        iid: 43,
        name: 'Pipeline',
        status: 'success',
        url: 'https://gitlab.example.com/redmine/redmine_dev_integration/-/pipelines/102',
        sha: 'abc123',
        ref: 'feature/AUTH-9999-login',
        created_at: '2026-05-25T10:00:00Z',
        updated_at: '2026-05-25T10:35:00Z'
      },
      project: {
        id: 456,
        web_url: 'https://gitlab.example.com/redmine/redmine_dev_integration'
      },
      user: {
        username: 'contributor',
        name: 'Contributor'
      },
      commit: {
        message: 'Fix AUTH-9999',
        title: 'Pipeline AUTH-9999'
      }
    }))

    assert_nothing_raised do
      assert @processor.call(event)
    end

    build = ExternalBuild.find_by!(
      provider: 'gitlab',
      external_repository: @external_repository,
      provider_build_id: '102'
    )
    assert_empty build.issues
  end

  def test_pipeline_hook_links_issue_via_sha_when_text_matching_finds_none
    project = Project.generate!(issue_key_prefix: 'AUTH')
    issue = Issue.generate!(project: project, subject: 'Trace target')
    @external_repository.update!(redmine_project: project)

    pull_request = ExternalPullRequest.create!(
      provider: 'gitlab',
      external_repository: @external_repository,
      number: 11,
      title: 'Trace MR',
      url: 'https://gitlab.example.com/redmine/redmine_dev_integration/-/merge_requests/11',
      state: 'open',
      merged: false,
      source_sha: 'abc123'
    )
    ExternalPullRequestIssue.create!(external_pull_request: pull_request, issue: issue)

    event = build_event(payload: JSON.generate({
      object_attributes: {
        id: 201,
        iid: 50,
        name: 'Pipeline',
        status: 'success',
        url: 'https://gitlab.example.com/redmine/redmine_dev_integration/-/pipelines/201',
        sha: 'abc123',
        ref: 'main',
        created_at: '2026-05-25T10:00:00Z',
        finished_at: '2026-05-25T11:00:00Z',
        updated_at: '2026-05-25T11:05:00Z'
      },
      project: {
        id: 456,
        web_url: 'https://gitlab.example.com/redmine/redmine_dev_integration'
      },
      user: {
        username: 'contributor',
        name: 'Contributor'
      },
      commit: {
        message: 'Refactor internal wiring',
        title: 'Pipeline'
      }
    }))

    assert @processor.call(event)

    build = ExternalBuild.find_by!(provider: 'gitlab', external_repository: @external_repository, provider_build_id: '201')
    assert_equal [issue.id], build.issues.pluck(:id)
    assert_equal 1, build.external_build_issues.count
  end
end
