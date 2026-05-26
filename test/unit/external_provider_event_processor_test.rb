# frozen_string_literal: true

require_relative '../test_helper'

class ExternalProviderEventProcessorTest < ActiveSupport::TestCase
  fixtures :projects, :repositories

  def setup
    @processor = RedmineDevIntegration::ExternalProviderEventProcessor.new
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
    @gitlab_repository = ExternalRepository.create!(
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
      provider: 'github',
      delivery_id: "delivery-#{SecureRandom.hex(4)}",
      event_type: 'push',
      payload: JSON.generate({
        ref: 'refs/heads/main',
        after: 'abc123',
        repository: {
          id: 123,
          html_url: 'https://github.com/redmine/redmine_dev_integration'
        }
      }),
      status: 'pending'
    }.merge(attributes))
  end

  def gitlab_push_payload(overrides = {})
    {
      object_kind: 'push',
      event_name: 'push',
      after: 'abc123',
      ref: 'refs/heads/main',
      project: {
        id: 456,
        web_url: 'https://gitlab.example.com/redmine/redmine_dev_integration'
      },
      repository: {
        id: 456,
        homepage: 'https://gitlab.example.com/redmine/redmine_dev_integration',
        url: 'https://gitlab.example.com/redmine/redmine_dev_integration'
      }
    }.deep_merge(overrides)
  end

  def gitlab_merge_request_payload(overrides = {})
    {
      object_kind: 'merge_request',
      event_type: 'merge_request',
      project: {
        id: 456,
        web_url: 'https://gitlab.example.com/redmine/redmine_dev_integration'
      },
      user: {
        username: 'contributor',
        name: 'Contributor'
      },
      object_attributes: {
        action: 'open',
        iid: 7,
        title: 'Add feature',
        description: 'Merge request body',
        web_url: 'https://gitlab.example.com/redmine/redmine_dev_integration/-/merge_requests/7',
        state: 'opened',
        merged: false,
        created_at: '2026-05-25T10:00:00Z',
        updated_at: '2026-05-25T11:00:00Z',
        source_branch: 'feature-branch',
        target_branch: 'main',
        last_commit: {id: 'source-sha'},
        diff_refs: {start_sha: 'target-sha'},
        merge_commit_sha: 'merge-sha',
        author: {
          username: 'contributor'
        }
      }
    }.deep_merge(overrides)
  end

  def gitlab_pipeline_payload(overrides = {})
    {
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
    }.deep_merge(overrides)
  end

  def gitlab_deployment_payload(overrides = {})
    {
      deployment_id: 9001,
      environment: 'staging',
      environment_external_url: 'https://staging.example.test',
      status: 'success',
      sha: 'abc123',
      ref: 'main',
      commit_title: 'Deploy to staging',
      user: {
        username: 'contributor',
        name: 'Contributor'
      },
      deployable_started_at: '2026-05-25T10:00:00Z',
      deployable_finished_at: '2026-05-25T10:20:00Z',
      created_at: '2026-05-25T10:00:00Z',
      updated_at: '2026-05-25T10:25:00Z',
      project: {
        id: 456,
        web_url: 'https://gitlab.example.com/redmine/redmine_dev_integration'
      }
    }.deep_merge(overrides)
  end

  def pull_request_payload(overrides = {})
    {
      action: 'opened',
      number: 7,
      repository: {
        id: 123,
        html_url: 'https://github.com/redmine/redmine_dev_integration'
      },
      pull_request: {
        title: 'Add feature',
        body: 'Pull request body',
        html_url: 'https://github.com/redmine/redmine_dev_integration/pull/7',
        state: 'open',
        merged: false,
        created_at: '2026-05-25T10:00:00Z',
        updated_at: '2026-05-25T11:00:00Z',
        user: {login: 'contributor'},
        head: {ref: 'feature-branch', sha: 'source-sha'},
        base: {ref: 'main', sha: 'target-sha'},
        merge_commit_sha: 'merge-sha'
      }
    }.deep_merge(overrides)
  end

  def test_branch_create_or_update_is_processed
    project = Project.generate!(issue_key_prefix: 'AUTH')
    issue = Issue.generate!(project: project, subject: 'Login fix')
    @external_repository.update!(redmine_project: project)

    event = build_event(payload: JSON.generate({
      ref: 'refs/heads/feature/AUTH-1-login',
      after: 'def456',
      repository: {
        id: 123,
        html_url: 'https://github.com/redmine/redmine_dev_integration'
      }
    }))

    with_captured_provider_event_logs do |processor, provider_event_logs|
      processor.call(event)

      branch = ExternalBranch.find_by!(external_repository: @external_repository, name: 'feature/AUTH-1-login')
      assert_equal 'active', branch.state
      assert_equal 'def456', branch.sha
      assert_equal 'https://github.com/redmine/redmine_dev_integration/tree/feature/AUTH-1-login', branch.url
      assert_equal [issue.id], branch.issues.pluck(:id)
      assert_equal 1, branch.external_branch_issues.count
      assert_equal 'processed', event.reload.status

      assert_equal 1, provider_event_logs.length
      log = provider_event_logs.last
      assert_equal 'processed', log[:status]
      assert_operator log[:duration_ms], :>=, 0
    end
  end

  def test_github_create_branch_event_creates_branch_and_links_issue
    project = Project.generate!(issue_key_prefix: 'AUTH')
    issue = Issue.generate!(project: project, subject: 'Create branch link')
    @external_repository.update!(redmine_project: project)

    event = build_event(
      event_type: 'create',
      payload: JSON.generate({
        ref: "feature/#{issue.issue_key}-login",
        ref_type: 'branch',
        repository: {
          id: 123,
          html_url: 'https://github.com/redmine/redmine_dev_integration'
        }
      })
    )

    @processor.call(event)

    branch = ExternalBranch.find_by!(external_repository: @external_repository, name: "feature/#{issue.issue_key}-login")
    assert_equal 'active', branch.state
    assert_equal "https://github.com/redmine/redmine_dev_integration/tree/feature/#{issue.issue_key}-login", branch.url
    assert_equal [issue.id], branch.issues.pluck(:id)
    assert_equal 'processed', event.reload.status
  end

  def test_github_create_branch_event_is_processed
    project = Project.generate!(issue_key_prefix: 'AUTH')
    issue = Issue.generate!(project: project, subject: 'Create event branch')
    @external_repository.update!(redmine_project: project)

    event = build_event(
      event_type: 'create',
      payload: JSON.generate({
        ref: 'feature/AUTH-1-login',
        ref_type: 'branch',
        repository: {
          id: 123,
          html_url: 'https://github.com/redmine/redmine_dev_integration',
          full_name: 'redmine/redmine_dev_integration'
        }
      })
    )

    @processor.call(event)

    branch = ExternalBranch.find_by!(external_repository: @external_repository, name: 'feature/AUTH-1-login')
    assert_equal 'active', branch.state
    assert_equal [issue.id], branch.issues.pluck(:id)
    assert_equal 'processed', event.reload.status
  end

  def test_github_repository_resolution_falls_back_to_full_name
    project = Project.generate!(issue_key_prefix: 'AUTH')
    issue = Issue.generate!(project: project, subject: 'Full name fallback')
    @external_repository.update!(
      redmine_project: project,
      provider_repository_id: 'owner/repo-alias',
      full_name: 'redmine/redmine_dev_integration'
    )

    event = build_event(payload: JSON.generate({
      ref: 'refs/heads/feature/AUTH-1-login',
      after: 'def456',
      repository: {
        id: 999_999,
        html_url: 'https://github.com/redmine/redmine_dev_integration',
        full_name: 'redmine/redmine_dev_integration'
      }
    }))

    @processor.call(event)

    branch = ExternalBranch.find_by!(external_repository: @external_repository, name: 'feature/AUTH-1-login')
    assert_equal [issue.id], branch.issues.pluck(:id)
    assert_equal 'processed', event.reload.status
  end

  def test_github_pull_request_repository_resolution_falls_back_to_full_name
    project = Project.generate!(issue_key_prefix: 'AUTH')
    issue = Issue.generate!(project: project, subject: 'PR fallback')
    @external_repository.update!(
      redmine_project: project,
      provider_repository_id: 'owner/repo-alias',
      full_name: 'redmine/redmine_dev_integration'
    )

    event = build_event(
      event_type: 'pull_request',
      payload: JSON.generate(
        pull_request_payload(
          repository: {
            id: 999_999,
            html_url: 'https://github.com/redmine/redmine_dev_integration',
            full_name: 'redmine/redmine_dev_integration'
          },
          pull_request: {
            title: "Fixes #{issue.issue_key}",
            body: 'PR body'
          }
        )
      )
    )

    @processor.call(event)

    pull_request = ExternalPullRequest.find_by!(external_repository: @external_repository, number: 7)
    assert_equal [issue.id], pull_request.issues.pluck(:id)
    assert_equal 'processed', event.reload.status
  end

  def test_branch_processing_leaves_issue_status_unchanged_when_automation_disabled
    project = Project.generate!(issue_key_prefix: 'AUTH')
    issue = Issue.generate!(project: project, subject: 'Login fix')
    @external_repository.update!(redmine_project: project)

    event = build_event(payload: JSON.generate({
      ref: 'refs/heads/feature/AUTH-1-login',
      after: 'def456',
      repository: {
        id: 123,
        html_url: 'https://github.com/redmine/redmine_dev_integration'
      }
    }))

    @processor.call(event)

    assert_equal issue.status_id, issue.reload.status_id
    assert_equal 1, issue.journals.count
    assert_match(/\[redmine-dev-integration:github:branch:/, issue.journals.last.notes)
    assert_equal 'processed', event.reload.status
  end

  def test_branch_delete_soft_deletes_existing_branch
    branch = ExternalBranch.create!(
      external_repository: @external_repository,
      name: 'feature/AUTH-1-login',
      url: 'https://github.com/redmine/redmine_dev_integration/tree/feature/AUTH-1-login',
      sha: 'abc123',
      state: 'active'
    )

    event = build_event(payload: JSON.generate({
      ref: 'refs/heads/feature/AUTH-1-login',
      deleted: true,
      after: 'def456',
      repository: {
        id: 123,
        html_url: 'https://github.com/redmine/redmine_dev_integration'
      }
    }))

    @processor.call(event)

    branch.reload
    assert_predicate branch, :deleted?
    assert_predicate branch.deleted_at, :present?
    assert_equal 'def456', branch.sha
    assert_equal 'processed', event.reload.status
  end

  def test_unmapped_repository_is_ignored
    event = build_event(payload: JSON.generate({
      ref: 'refs/heads/main',
      after: 'def456',
      repository: {
        id: 999,
        html_url: 'https://github.com/other/repo'
      }
    }))

    with_captured_provider_event_logs do |processor, provider_event_logs|
      processor.call(event)

      assert_nil ExternalBranch.find_by(external_repository: @external_repository, name: 'main')
      assert_equal 'ignored', event.reload.status

      assert_equal 1, provider_event_logs.length
      log = provider_event_logs.last
      assert_equal 'ignored', log[:status]
      assert_operator log[:duration_ms], :>=, 0
    end
  end

  def test_inactive_github_repository_does_not_create_branch_pull_request_or_deployment_records
    @external_repository.update!(active: false)

    branch_event = build_event(payload: JSON.generate({
      ref: 'refs/heads/main',
      after: 'def456',
      repository: {
        id: 123,
        html_url: 'https://github.com/redmine/redmine_dev_integration'
      }
    }))

    pull_request_event = build_event(
      event_type: 'pull_request',
      payload: JSON.generate(pull_request_payload(
        action: 'opened',
        repository: {
          id: 123,
          html_url: 'https://github.com/redmine/redmine_dev_integration'
        },
        pull_request: {
          title: 'Fix AUTH-1',
          body: 'Refs AUTH-1',
          head: {ref: 'feature/AUTH-1'}
        }
      ))
    )

    deployment_event = build_event(
      event_type: 'deployment_status',
      payload: JSON.generate({
        repository: {
          id: 123,
          html_url: 'https://github.com/redmine/redmine_dev_integration'
        },
        deployment: {
          id: 77,
          environment: 'production',
          sha: 'abc123',
          ref: 'main',
          created_at: '2026-05-25T10:00:00Z',
          creator: {login: 'contributor'}
        },
        deployment_status: {
          state: 'success',
          environment_url: 'https://prod.example.test',
          created_at: '2026-05-25T10:05:00Z',
          updated_at: '2026-05-25T10:05:00Z'
        }
      })
    )

    [branch_event, pull_request_event, deployment_event].each { |event| @processor.call(event) }

    assert_nil ExternalBranch.find_by(external_repository: @external_repository, name: 'main')
    assert_nil ExternalPullRequest.find_by(external_repository: @external_repository, number: 7)
    assert_nil ExternalDeployment.find_by(provider: 'github', external_repository: @external_repository, provider_deployment_id: '77')
  end

  def test_inactive_gitlab_repository_does_not_create_branch_pull_request_build_or_deployment_records
    @gitlab_repository.update!(active: false)

    push_event = build_event(
      provider: 'gitlab',
      event_type: 'Push Hook',
      payload: JSON.generate(gitlab_push_payload(
        ref: 'refs/heads/main',
        after: 'def456'
      ))
    )

    merge_request_event = build_event(
      provider: 'gitlab',
      event_type: 'Merge Request Hook',
      payload: JSON.generate(gitlab_merge_request_payload(
        object_attributes: {
          action: 'open',
          title: 'Fix AUTH-1',
          description: 'Refs AUTH-1',
          source_branch: 'feature/AUTH-1',
          target_branch: 'main',
          state: 'opened',
          merged: false
        }
      ))
    )

    pipeline_event = build_event(
      provider: 'gitlab',
      event_type: 'Pipeline Hook',
      payload: JSON.generate(gitlab_pipeline_payload(
        object_attributes: {
          id: 101,
          iid: 42,
          name: 'Pipeline',
          status: 'success',
          ref: 'main',
          sha: 'abc123',
          created_at: '2026-05-25T10:00:00Z',
          updated_at: '2026-05-25T10:35:00Z'
        }
      ))
    )

    deployment_event = build_event(
      provider: 'gitlab',
      event_type: 'Deployment Hook',
      payload: JSON.generate(gitlab_deployment_payload(
        environment: 'production',
        status: 'success',
        ref: 'main'
      ))
    )

    [push_event, merge_request_event, pipeline_event, deployment_event].each { |event| @processor.call(event) }

    assert_nil ExternalBranch.find_by(external_repository: @gitlab_repository, name: 'main')
    assert_nil ExternalPullRequest.find_by(external_repository: @gitlab_repository, number: 7)
    assert_nil ExternalBuild.find_by(provider: 'gitlab', external_repository: @gitlab_repository, provider_build_id: '101')
    assert_nil ExternalDeployment.find_by(provider: 'gitlab', external_repository: @gitlab_repository, provider_deployment_id: '9001', environment_name: 'production')
  end

  def test_non_branch_ref_is_ignored
    event = build_event(payload: JSON.generate({
      ref: 'refs/tags/v1.0.0',
      after: 'def456',
      repository: {
        id: 123,
        html_url: 'https://github.com/redmine/redmine_dev_integration'
      }
    }))

    @processor.call(event)

    assert_nil ExternalBranch.find_by(external_repository: @external_repository, name: 'v1.0.0')
    assert_equal 'ignored', event.reload.status
  end

  def test_pull_request_open_creates_record
    project = Project.generate!(issue_key_prefix: 'AUTH')
    issue_one = Issue.generate!(project: project, subject: 'Login fix')
    issue_two = Issue.generate!(project: project, subject: 'Docs fix')
    @external_repository.update!(redmine_project: project)

    event = build_event(
      event_type: 'pull_request',
      payload: JSON.generate(pull_request_payload(
        pull_request: {
          title: "Fix #{issue_one.issue_key}",
          body: "Also closes #{issue_two.issue_key}\nRefs #{issue_one.issue_key}",
          head: {ref: "feature/#{issue_one.issue_key}-branch"}
        }
      ))
    )

    @processor.call(event)

    pull_request = ExternalPullRequest.find_by!(external_repository: @external_repository, number: 7)
    assert_equal "Fix #{issue_one.issue_key}", pull_request.title
    assert_equal "Also closes #{issue_two.issue_key}\nRefs #{issue_one.issue_key}", pull_request.body
    assert_equal 'https://github.com/redmine/redmine_dev_integration/pull/7', pull_request.url
    assert_equal 'open', pull_request.state
    assert_equal 'contributor', pull_request.author_login
    assert_equal "feature/#{issue_one.issue_key}-branch", pull_request.source_branch
    assert_equal 'main', pull_request.target_branch
    assert_equal 'source-sha', pull_request.source_sha
    assert_equal 'target-sha', pull_request.target_sha
    assert_equal 'merge-sha', pull_request.merge_commit_sha
    assert_not_predicate pull_request, :merged
    assert_equal Time.zone.parse('2026-05-25T10:00:00Z'), pull_request.opened_at
    assert_equal Time.zone.parse('2026-05-25T11:00:00Z'), pull_request.last_event_at
    assert_equal [issue_one.id, issue_two.id], pull_request.issues.pluck(:id)
    assert_equal 2, pull_request.external_pull_request_issues.count
    assert_equal 'processed', event.reload.status
  end

  def test_enabled_pull_request_open_changes_linked_issue_status
    project = Project.generate!(issue_key_prefix: 'AUTH')
    issue = Issue.generate!(project: project, subject: 'Login fix')
    setting = DevelopmentIntegrationProjectSetting.create!(
      project: project,
      automation_enabled: true,
      pr_opened_status: issue_statuses(:issue_statuses_002)
    )
    @external_repository.update!(redmine_project: project)

    event = build_event(
      event_type: 'pull_request',
      payload: JSON.generate(pull_request_payload(
        action: 'opened',
        pull_request: {
          title: "Fix #{issue.issue_key}",
          body: "Refs #{issue.issue_key}",
          html_url: 'https://github.com/redmine/redmine_dev_integration/pull/7',
          state: 'open',
          merged: false,
          head: {ref: "feature/#{issue.issue_key}-branch"},
          base: {ref: 'main'}
        }
      ))
    )

    @processor.call(event)

    assert_equal issue_statuses(:issue_statuses_002).id, issue.reload.status_id
    assert_equal 1, issue.journals.count
    assert_includes issue.journals.last.notes, 'PR opened: #7'
    assert_equal 'processed', event.reload.status
    assert_predicate setting.reload, :automation_enabled
  end

  def test_supported_pull_request_closed_merged_changes_linked_issue_status
    project = Project.generate!(issue_key_prefix: 'AUTH')
    issue = Issue.generate!(project: project, subject: 'Login fix')
    setting = DevelopmentIntegrationProjectSetting.create!(
      project: project,
      automation_enabled: true,
      pr_merged_status: issue_statuses(:issue_statuses_003)
    )
    @external_repository.update!(redmine_project: project)

    event = build_event(
      event_type: 'pull_request',
      payload: JSON.generate(pull_request_payload(
        action: 'closed',
        pull_request: {
          title: "Fix #{issue.issue_key}",
          body: "Refs #{issue.issue_key}",
          html_url: 'https://github.com/redmine/redmine_dev_integration/pull/7',
          state: 'closed',
          merged: true,
          closed_at: '2026-05-25T12:00:00Z',
          merged_at: '2026-05-25T12:05:00Z',
          updated_at: '2026-05-25T12:10:00Z',
          head: {ref: "feature/#{issue.issue_key}-branch"},
          base: {ref: 'main'}
        }
      ))
    )

    @processor.call(event)

    assert_equal issue_statuses(:issue_statuses_003).id, issue.reload.status_id
    assert_equal 1, issue.journals.count
    assert_includes issue.journals.last.notes, 'PR merged: #7'
    assert_includes issue.journals.last.notes, '[redmine-dev-integration:github:pr:'
    pull_request = ExternalPullRequest.find_by!(external_repository: @external_repository, number: 7)
    assert_equal 'source-sha', pull_request.source_sha
    assert_equal 'target-sha', pull_request.target_sha
    assert_equal 'merge-sha', pull_request.merge_commit_sha
    assert_equal 'processed', event.reload.status
    assert_predicate setting.reload, :automation_enabled
  end

  def test_supported_pull_request_closed_without_merge_adds_note_only_when_enabled
    project = Project.generate!(issue_key_prefix: 'AUTH')
    issue = Issue.generate!(project: project, subject: 'Login fix')
    setting = DevelopmentIntegrationProjectSetting.create!(
      project: project,
      automation_enabled: true,
      pr_closed_note_enabled: true
    )
    @external_repository.update!(redmine_project: project)

    event = build_event(
      event_type: 'pull_request',
      payload: JSON.generate(pull_request_payload(
        action: 'closed',
        pull_request: {
          title: "Fix #{issue.issue_key}",
          body: "Refs #{issue.issue_key}",
          html_url: 'https://github.com/redmine/redmine_dev_integration/pull/7',
          state: 'closed',
          merged: false,
          closed_at: '2026-05-25T12:00:00Z',
          updated_at: '2026-05-25T12:10:00Z',
          head: {ref: "feature/#{issue.issue_key}-branch"},
          base: {ref: 'main'}
        }
      ))
    )

    @processor.call(event)

    assert_equal issue.status_id, issue.reload.status_id
    assert_equal 1, issue.journals.count
    assert_includes issue.journals.last.notes, 'PR closed without merge: #7'
    assert_equal 'processed', event.reload.status
    assert_predicate setting.reload, :automation_enabled
  end

  def test_unsupported_pull_request_action_updates_record_without_automation_side_effects
    project = Project.generate!(issue_key_prefix: 'AUTH')
    issue = Issue.generate!(project: project, subject: 'Login fix')
    setting = DevelopmentIntegrationProjectSetting.create!(
      project: project,
      automation_enabled: true,
      pr_opened_status: issue_statuses(:issue_statuses_002)
    )
    @external_repository.update!(redmine_project: project)

    event = build_event(
      event_type: 'pull_request',
      payload: JSON.generate(pull_request_payload(
        action: 'edited',
        pull_request: {
          title: "Fix #{issue.issue_key}",
          body: "Refs #{issue.issue_key}",
          html_url: 'https://github.com/redmine/redmine_dev_integration/pull/7',
          state: 'open',
          merged: false,
          head: {ref: "feature/#{issue.issue_key}-branch"},
          base: {ref: 'main'}
        }
      ))
    )

    @processor.call(event)

    pull_request = ExternalPullRequest.find_by!(external_repository: @external_repository, number: 7)
    assert_equal "Fix #{issue.issue_key}", pull_request.title
    assert_equal [issue.id], pull_request.issues.pluck(:id)
    assert_equal issue.status_id, issue.reload.status_id
    assert_equal 0, issue.journals.count
    assert_equal 'processed', event.reload.status
    assert_predicate setting.reload, :automation_enabled
  end

  def test_repeated_supported_pull_request_event_does_not_duplicate_automation_journal
    project = Project.generate!(issue_key_prefix: 'AUTH')
    issue = Issue.generate!(project: project, subject: 'Login fix')
    setting = DevelopmentIntegrationProjectSetting.create!(
      project: project,
      automation_enabled: true,
      pr_opened_status: issue_statuses(:issue_statuses_002)
    )
    @external_repository.update!(redmine_project: project)

    payload = JSON.generate(pull_request_payload(
      action: 'opened',
      pull_request: {
        title: "Fix #{issue.issue_key}",
        body: "Refs #{issue.issue_key}",
        html_url: 'https://github.com/redmine/redmine_dev_integration/pull/7',
        state: 'open',
        merged: false,
        head: {ref: "feature/#{issue.issue_key}-branch"},
        base: {ref: 'main'}
      }
    ))

    first_event = build_event(event_type: 'pull_request', payload: payload)
    second_event = build_event(event_type: 'pull_request', payload: payload)

    @processor.call(first_event)
    assert_equal 1, issue.journals.count

    assert_no_difference 'issue.reload.journals.count' do
      @processor.call(second_event)
    end
    assert_equal issue_statuses(:issue_statuses_002).id, issue.reload.status_id
    assert_equal 'processed', second_event.reload.status
    assert_predicate setting.reload, :automation_enabled
  end

  def test_pull_request_closed_merged_updates_merged_fields
    ExternalPullRequest.create!(
      provider: 'github',
      external_repository: @external_repository,
      number: 7,
      title: 'Add feature',
      body: 'Pull request body',
      url: 'https://github.com/redmine/redmine_dev_integration/pull/7',
      state: 'open',
      merged: false
    )

    event = build_event(
      event_type: 'pull_request',
      payload: JSON.generate(pull_request_payload(
        action: 'closed',
        pull_request: {
          state: 'closed',
          merged: true,
          closed_at: '2026-05-25T12:00:00Z',
          merged_at: '2026-05-25T12:05:00Z',
          updated_at: '2026-05-25T12:10:00Z'
        }
      ))
    )

    @processor.call(event)

    pull_request = ExternalPullRequest.find_by!(external_repository: @external_repository, number: 7)
    assert_equal 'closed', pull_request.state
    assert_predicate pull_request, :merged
    assert_equal Time.zone.parse('2026-05-25T12:05:00Z'), pull_request.merged_at
    assert_equal Time.zone.parse('2026-05-25T12:00:00Z'), pull_request.closed_at
    assert_equal Time.zone.parse('2026-05-25T12:10:00Z'), pull_request.last_event_at
    assert_equal 'processed', event.reload.status
  end

  def test_branch_event_with_automation_enabled_changes_issue_status
    project = Project.generate!(issue_key_prefix: 'AUTH')
    issue = Issue.generate!(project: project, subject: 'Login fix')
    setting = DevelopmentIntegrationProjectSetting.create!(
      project: project,
      automation_enabled: true,
      branch_created_status: issue_statuses(:issue_statuses_001)
    )
    @external_repository.update!(redmine_project: project)

    event = build_event(payload: JSON.generate({
      ref: "refs/heads/feature/#{issue.issue_key}-login",
      after: 'def456',
      repository: {
        id: 123,
        html_url: 'https://github.com/redmine/redmine_dev_integration'
      }
    }))

    @processor.call(event)

    assert_equal issue_statuses(:issue_statuses_001).id, issue.reload.status_id
    assert_equal 1, issue.journals.count
    assert_includes issue.journals.last.notes, '[redmine-dev-integration:github:branch:'
    assert_includes issue.journals.last.notes, 'Branch created/activated:'
    assert_equal 'processed', event.reload.status
    assert_predicate setting.reload, :automation_enabled
  end

  def test_repeated_branch_event_with_automation_enabled_does_not_duplicate_journal
    project = Project.generate!(issue_key_prefix: 'AUTH')
    issue = Issue.generate!(project: project, subject: 'Login fix')
    setting = DevelopmentIntegrationProjectSetting.create!(
      project: project,
      automation_enabled: true,
      branch_created_status: issue_statuses(:issue_statuses_001)
    )
    @external_repository.update!(redmine_project: project)

    payload = JSON.generate({
      ref: 'refs/heads/feature/AUTH-1-login',
      after: 'def456',
      repository: {
        id: 123,
        html_url: 'https://github.com/redmine/redmine_dev_integration'
      }
    })

    event_one = build_event(payload: payload)
    event_two = build_event(payload: payload)

    @processor.call(event_one)

    assert_equal 1, issue.reload.journals.count
    assert_includes issue.journals.last.notes, '[redmine-dev-integration:github:branch:'
    assert_includes issue.journals.last.notes, 'Branch created/activated:'

    assert_no_difference 'issue.reload.journals.count' do
      @processor.call(event_two)
    end

    assert_equal issue_statuses(:issue_statuses_001).id, issue.reload.status_id
    assert_equal 'processed', event_two.reload.status
    assert_predicate setting.reload, :automation_enabled
  end

  def test_gitlab_branch_create_update_links_and_updates_sha
    project = Project.generate!(issue_key_prefix: 'AUTH')
    issue = Issue.generate!(project: project, subject: 'Login fix')
    @gitlab_repository.update!(redmine_project: project)

    first_event = build_event(
      provider: 'gitlab',
      event_type: 'Push Hook',
      payload: JSON.generate(gitlab_push_payload(
        ref: "refs/heads/feature/#{issue.issue_key}-login",
        after: 'def456'
      ))
    )

    @processor.call(first_event)

    branch = ExternalBranch.find_by!(external_repository: @gitlab_repository, name: "feature/#{issue.issue_key}-login")
    assert_equal 'active', branch.state
    assert_equal 'def456', branch.sha
    assert_equal "https://gitlab.example.com/redmine/redmine_dev_integration/-/tree/feature/#{issue.issue_key}-login", branch.url
    assert_equal [issue.id], branch.issues.pluck(:id)
    assert_equal 1, branch.external_branch_issues.count
    assert_equal 'processed', first_event.reload.status

    second_event = build_event(
      provider: 'gitlab',
      event_type: 'Push Hook',
      payload: JSON.generate(gitlab_push_payload(
        ref: "refs/heads/feature/#{issue.issue_key}-login",
        after: 'def789'
      ))
    )

    @processor.call(second_event)

    assert_equal 1, ExternalBranch.where(external_repository: @gitlab_repository, name: "feature/#{issue.issue_key}-login").count
    assert_equal 'def789', branch.reload.sha
    assert_equal 'processed', second_event.reload.status
  end

  def test_gitlab_branch_delete_soft_deletes_existing_branch
    branch = ExternalBranch.create!(
      external_repository: @gitlab_repository,
      name: 'feature/AUTH-1-login',
      url: 'https://gitlab.example.com/redmine/redmine_dev_integration/-/tree/feature/AUTH-1-login',
      sha: 'abc123',
      state: 'active'
    )

    event = build_event(
      provider: 'gitlab',
      event_type: 'Push Hook',
      payload: JSON.generate(gitlab_push_payload(
        ref: 'refs/heads/feature/AUTH-1-login',
        after: '0' * 40,
        deleted: true
      ))
    )

    @processor.call(event)

    branch.reload
    assert_predicate branch, :deleted?
    assert_predicate branch.deleted_at, :present?
    assert_equal '0' * 40, branch.sha
    assert_equal 'processed', event.reload.status
  end

  def test_gitlab_unsupported_event_is_ignored
    event = build_event(
      provider: 'gitlab',
      event_type: 'Issue Hook',
      payload: JSON.generate(gitlab_push_payload)
    )

    @processor.call(event)

    assert_nil ExternalBranch.find_by(external_repository: @gitlab_repository, name: 'main')
    assert_nil ExternalPullRequest.find_by(external_repository: @gitlab_repository, number: 7)
    assert_equal 'ignored', event.reload.status
  end

  def test_gitlab_pipeline_hook_is_dispatched
    project = Project.generate!(issue_key_prefix: 'AUTH')
    issue = Issue.generate!(project: project, subject: 'Login fix')
    @gitlab_repository.update!(redmine_project: project)

    event = build_event(
      provider: 'gitlab',
      event_type: 'Pipeline Hook',
      payload: JSON.generate(gitlab_pipeline_payload(
        object_attributes: {
          name: "Pipeline for #{issue.issue_key}",
          status: 'success',
          ref: "feature/#{issue.issue_key}-login",
          sha: 'def456',
          created_at: '2026-05-25T10:00:00Z',
          updated_at: '2026-05-25T10:30:00Z'
        },
        commit: {
          message: "Fix #{issue.issue_key}",
          title: "Pipeline #{issue.issue_key}"
        }
      ))
    )

    @processor.call(event)

    build = ExternalBuild.find_by!(provider: 'gitlab', external_repository: @gitlab_repository, provider_build_id: '101')
    assert_equal 'processed', event.reload.status
    assert_equal [issue.id], build.issues.pluck(:id)
  end

  def test_gitlab_pipeline_success_with_automation_enabled_changes_linked_issue_status_and_deduplicates
    project = Project.generate!(issue_key_prefix: 'AUTH')
    issue = Issue.generate!(project: project, subject: 'Login fix')
    setting = DevelopmentIntegrationProjectSetting.create!(
      project: project,
      automation_enabled: true,
      build_success_status: issue_statuses(:issue_statuses_002)
    )
    @gitlab_repository.update!(redmine_project: project)

    payload = JSON.generate(gitlab_pipeline_payload(
      object_attributes: {
        name: "Pipeline for #{issue.issue_key}",
        status: 'success',
        ref: "feature/#{issue.issue_key}-login",
        sha: 'def456',
        created_at: '2026-05-25T10:00:00Z',
        updated_at: '2026-05-25T10:30:00Z'
      },
      commit: {
        message: "Fix #{issue.issue_key}",
        title: "Pipeline #{issue.issue_key}"
      }
    ))

    first_event = build_event(provider: 'gitlab', event_type: 'Pipeline Hook', payload: payload)
    second_event = build_event(provider: 'gitlab', event_type: 'Pipeline Hook', payload: payload)

    @processor.call(first_event)

    build = ExternalBuild.find_by!(provider: 'gitlab', external_repository: @gitlab_repository, provider_build_id: '101')
    assert_equal issue_statuses(:issue_statuses_002).id, issue.reload.status_id
    assert_equal 1, issue.journals.count
    assert_includes issue.journals.last.notes, '[redmine-dev-integration:build:gitlab:'
    assert_equal [issue.id], build.issues.pluck(:id)
    assert_equal 'processed', first_event.reload.status

    assert_no_difference 'issue.reload.journals.count' do
      @processor.call(second_event)
    end

    assert_equal issue_statuses(:issue_statuses_002).id, issue.reload.status_id
    assert_equal 'processed', second_event.reload.status
    assert_predicate setting.reload, :automation_enabled
  end

  def test_gitlab_deployment_hook_is_dispatched
    project = Project.generate!(issue_key_prefix: 'AUTH')
    issue = Issue.generate!(project: project, subject: 'Deployment target')
    @gitlab_repository.update!(redmine_project: project)

    event = build_event(
      provider: 'gitlab',
      event_type: 'Deployment Hook',
      payload: JSON.generate(gitlab_deployment_payload(
        environment: 'production',
        status: 'success',
        ref: "feature/#{issue.issue_key}-login",
        commit_title: "Deploy #{issue.issue_key} to production"
      ))
    )

    @processor.call(event)

    deployment = ExternalDeployment.find_by!(
      provider: 'gitlab',
      external_repository: @gitlab_repository,
      provider_deployment_id: '9001',
      environment_name: 'production'
    )
    assert_equal 'processed', event.reload.status
    assert_equal [issue.id], deployment.issues.pluck(:id)
  end

  def test_gitlab_deployment_failure_with_automation_enabled_changes_linked_issue_status_and_deduplicates
    project = Project.generate!(issue_key_prefix: 'AUTH')
    issue = Issue.generate!(project: project, subject: 'Deployment target')
    setting = DevelopmentIntegrationProjectSetting.create!(
      project: project,
      automation_enabled: true,
      deployment_failed_note_enabled: true,
      deployment_failed_status: issue_statuses(:issue_statuses_003)
    )
    @gitlab_repository.update!(redmine_project: project)

    payload = JSON.generate(gitlab_deployment_payload(
      environment: 'production',
      status: 'failed',
      ref: "feature/#{issue.issue_key}-login",
      commit_title: "Deploy #{issue.issue_key} to production"
    ))

    first_event = build_event(provider: 'gitlab', event_type: 'Deployment Hook', payload: payload)
    second_event = build_event(provider: 'gitlab', event_type: 'Deployment Hook', payload: payload)

    @processor.call(first_event)

    deployment = ExternalDeployment.find_by!(
      provider: 'gitlab',
      external_repository: @gitlab_repository,
      provider_deployment_id: '9001',
      environment_name: 'production'
    )
    assert_equal issue_statuses(:issue_statuses_003).id, issue.reload.status_id
    assert_equal 1, issue.journals.count
    assert_includes issue.journals.last.notes, 'Deployment failed: production'
    assert_includes issue.journals.last.notes, '[redmine-dev-integration:deployment:gitlab:'
    assert_equal [issue.id], deployment.issues.pluck(:id)
    assert_equal 'processed', first_event.reload.status

    assert_no_difference 'issue.reload.journals.count' do
      @processor.call(second_event)
    end

    assert_equal issue_statuses(:issue_statuses_003).id, issue.reload.status_id
    assert_equal 'processed', second_event.reload.status
    assert_predicate setting.reload, :automation_enabled
  end

  def test_gitlab_merge_request_open_creates_record_and_links_issues
    project = Project.generate!(issue_key_prefix: 'AUTH')
    issue_one = Issue.generate!(project: project, subject: 'Login fix')
    issue_two = Issue.generate!(project: project, subject: 'Docs fix')
    @gitlab_repository.update!(redmine_project: project)

    event = build_event(
      provider: 'gitlab',
      event_type: 'Merge Request Hook',
      payload: JSON.generate(gitlab_merge_request_payload(
        object_attributes: {
          action: 'open',
          title: "Fix #{issue_one.issue_key}",
          description: "Also closes #{issue_two.issue_key}\nRefs #{issue_one.issue_key}",
          source_branch: "feature/#{issue_one.issue_key}-branch",
          target_branch: 'main',
          state: 'opened',
          merged: false
        }
      ))
    )

    @processor.call(event)

    pull_request = ExternalPullRequest.find_by!(external_repository: @gitlab_repository, number: 7)
    assert_equal 'gitlab', pull_request.provider
    assert_equal "Fix #{issue_one.issue_key}", pull_request.title
    assert_equal "Also closes #{issue_two.issue_key}\nRefs #{issue_one.issue_key}", pull_request.body
    assert_equal 'https://gitlab.example.com/redmine/redmine_dev_integration/-/merge_requests/7', pull_request.url
    assert_equal 'open', pull_request.state
    assert_equal 'contributor', pull_request.author_login
    assert_equal "feature/#{issue_one.issue_key}-branch", pull_request.source_branch
    assert_equal 'main', pull_request.target_branch
    assert_equal 'source-sha', pull_request.source_sha
    assert_equal 'target-sha', pull_request.target_sha
    assert_equal 'merge-sha', pull_request.merge_commit_sha
    assert_not_predicate pull_request, :merged
    assert_equal Time.zone.parse('2026-05-25T10:00:00Z'), pull_request.opened_at
    assert_equal Time.zone.parse('2026-05-25T11:00:00Z'), pull_request.last_event_at
    assert_equal [issue_one.id, issue_two.id], pull_request.issues.pluck(:id)
    assert_equal 2, pull_request.external_pull_request_issues.count
    assert_equal 'processed', event.reload.status
  end

  def test_gitlab_merge_request_merge_updates_record_and_changes_linked_issue_status
    project = Project.generate!(issue_key_prefix: 'AUTH')
    issue = Issue.generate!(project: project, subject: 'Login fix')
    setting = DevelopmentIntegrationProjectSetting.create!(
      project: project,
      automation_enabled: true,
      pr_merged_status: issue_statuses(:issue_statuses_003)
    )
    @gitlab_repository.update!(redmine_project: project)

    opened_event = build_event(
      provider: 'gitlab',
      event_type: 'Merge Request Hook',
      payload: JSON.generate(gitlab_merge_request_payload(
        object_attributes: {
          action: 'open',
          title: "Fix #{issue.issue_key}",
          description: "Refs #{issue.issue_key}",
          source_branch: "feature/#{issue.issue_key}-branch",
          target_branch: 'main',
          state: 'opened',
          merged: false
        }
      ))
    )

    @processor.call(opened_event)

    merged_event = build_event(
      provider: 'gitlab',
      event_type: 'Merge Request Hook',
      payload: JSON.generate(gitlab_merge_request_payload(
        object_attributes: {
          action: 'merge',
          title: "Fix #{issue.issue_key}",
          description: "Refs #{issue.issue_key}",
          source_branch: "feature/#{issue.issue_key}-branch",
          target_branch: 'main',
          state: 'merged',
          merged: true,
          merged_at: '2026-05-25T12:05:00Z',
          closed_at: '2026-05-25T12:00:00Z',
          updated_at: '2026-05-25T12:10:00Z'
        }
      ))
    )

    @processor.call(merged_event)

    pull_request = ExternalPullRequest.find_by!(external_repository: @gitlab_repository, number: 7)
    assert_equal 'closed', pull_request.state
    assert_predicate pull_request, :merged
    assert_equal Time.zone.parse('2026-05-25T12:05:00Z'), pull_request.merged_at
    assert_equal Time.zone.parse('2026-05-25T12:00:00Z'), pull_request.closed_at
    assert_equal Time.zone.parse('2026-05-25T12:10:00Z'), pull_request.last_event_at
    assert_equal 'source-sha', pull_request.source_sha
    assert_equal 'target-sha', pull_request.target_sha
    assert_equal 'merge-sha', pull_request.merge_commit_sha
    assert_equal issue_statuses(:issue_statuses_003).id, issue.reload.status_id
    assert_equal 1, issue.journals.count
    assert_includes issue.journals.last.notes, 'PR merged: #7'
    assert_includes issue.journals.last.notes, '[redmine-dev-integration:gitlab:pr:'
    assert_equal 'processed', merged_event.reload.status
    assert_predicate setting.reload, :automation_enabled
  end

  def test_unmapped_pull_request_repository_is_ignored
    event = build_event(
      event_type: 'pull_request',
      payload: JSON.generate(pull_request_payload(repository: {id: 999, html_url: 'https://github.com/other/repo'}))
    )

    @processor.call(event)

    assert_nil ExternalPullRequest.find_by(external_repository: @external_repository, number: 7)
    assert_equal 'ignored', event.reload.status
  end

  def test_non_pull_request_event_is_still_ignored
    event = build_event(
      event_type: 'issues',
      payload: JSON.generate(pull_request_payload)
    )

    @processor.call(event)

    assert_nil ExternalPullRequest.find_by(external_repository: @external_repository, number: 7)
    assert_equal 'ignored', event.reload.status
  end

  def test_processor_logs_failed_result_when_provider_handler_raises
    event = build_event(payload: JSON.generate({
      ref: 'refs/heads/main',
      after: 'def456',
      repository: {
        id: 123,
        html_url: 'https://github.com/redmine/redmine_dev_integration'
      }
    }))

    with_captured_provider_event_logs do |processor, provider_event_logs|
      raising_provider_processor = Object.new
      raising_provider_processor.define_singleton_method(:call) do |_external_provider_event|
        raise StandardError, 'boom'
      end
      processor.define_singleton_method(:github_push_branch_processor) do
        raising_provider_processor
      end

      processor.call(event)

      assert_equal 'failed', event.reload.status
      assert_equal 1, provider_event_logs.length
      log = provider_event_logs.last
      assert_equal 'failed', log[:status]
      assert_equal 'StandardError', log[:error_class]
      assert_equal 'boom', log[:error_message]
      assert_operator log[:duration_ms], :>=, 0
    end
  end

  def test_logger_exception_does_not_break_event_processing
    raising_provider_event_logger = Object.new
    raising_provider_event_logger.define_singleton_method(:call) do |*_args, **_kwargs|
      raise StandardError, 'logger boom'
    end

    processor = RedmineDevIntegration::ExternalProviderEventProcessor.new
    processor.define_singleton_method(:provider_event_logger) do
      raising_provider_event_logger
    end

    event = build_event(payload: JSON.generate({
      ref: 'refs/heads/main',
      after: 'def456',
      repository: {
        id: 123,
        html_url: 'https://github.com/redmine/redmine_dev_integration'
      }
    }))

    processor.call(event)

    assert_equal 'processed', event.reload.status
  end

  def test_repeated_branch_event_does_not_duplicate_audit_note
    project = Project.generate!(issue_key_prefix: 'AUTH')
    issue = Issue.generate!(project: project, subject: 'Login fix')
    @external_repository.update!(redmine_project: project)

    payload = JSON.generate({
      ref: 'refs/heads/feature/AUTH-1-login',
      after: 'def456',
      repository: {
        id: 123,
        html_url: 'https://github.com/redmine/redmine_dev_integration'
      }
    })

    event_one = build_event(payload: payload)
    event_two = build_event(payload: payload)

    @processor.call(event_one)
    assert_difference 'issue.reload.journals.count', 0 do
      @processor.call(event_two)
    end
  end

  private

  def with_captured_provider_event_logs
    provider_event_logs = []
    fake_provider_event_logger = Object.new
    fake_provider_event_logger.define_singleton_method(:call) do |external_provider_event, status:, duration_ms:, error: nil|
      provider_event_logs << {
        external_provider_event: external_provider_event,
        status: status,
        duration_ms: duration_ms,
        error_class: error&.class&.name,
        error_message: error&.message,
      }
      nil
    end

    processor = RedmineDevIntegration::ExternalProviderEventProcessor.new
    processor.define_singleton_method(:provider_event_logger) do
      fake_provider_event_logger
    end

    yield processor, provider_event_logs
  end
end
