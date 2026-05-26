# Build + Deployment Integration Execution Breakdown

This file is written for low-cost subagents. Each work packet should be small enough to execute with local source inspection and focused tests.

## Ground Rules

- Feature lives inside `plugins/redmine_dev_integration`.
- Do not create a third plugin.
- Do not touch `redmine_issue_keys` except to rely on its public lookup behavior through `IssueLinker`.
- Do not override core Redmine views.
- Extend the existing Development tab hook and partial.
- Keep numeric Redmine issue IDs working.
- Keep existing branch, PR/MR, webhook, audit, and automation behavior working.
- Use shared issue-key parsing through `RedmineDevIntegration::IssueLinker`; do not add duplicate regexes.
- Store events even when no issue is linked.
- Deduplicate semantic records by provider object IDs, not only webhook delivery IDs.
- Automation remains disabled by default.

## Current Extension Points

Read these first before implementing any packet:

- Event dispatch: `plugins/redmine_dev_integration/lib/redmine_dev_integration/external_provider_event_processor.rb`
- Issue linking: `plugins/redmine_dev_integration/lib/redmine_dev_integration/issue_linker.rb`
- GitHub webhook controller: `plugins/redmine_dev_integration/app/controllers/dev_integrations/github_webhooks_controller.rb`
- GitLab webhook controller: `plugins/redmine_dev_integration/app/controllers/dev_integrations/gitlab_webhooks_controller.rb`
- Branch model pattern: `plugins/redmine_dev_integration/app/models/external_branch.rb`
- PR model pattern: `plugins/redmine_dev_integration/app/models/external_pull_request.rb`
- Development panel data: `plugins/redmine_dev_integration/lib/redmine_dev_integration/issue_development_panel_data.rb`
- Development tab partial: `plugins/redmine_dev_integration/app/views/issues/tabs/_development.html.erb`
- Project setting model: `plugins/redmine_dev_integration/app/models/development_integration_project_setting.rb`
- Project setting migration: `plugins/redmine_dev_integration/db/migrate/006_create_development_integration_project_settings.rb`
- Automation service: `plugins/redmine_dev_integration/lib/redmine_dev_integration/automation_service.rb`
- Audit note service: `plugins/redmine_dev_integration/lib/redmine_dev_integration/audit_note_service.rb`

## Supported V1 Events

- GitHub `workflow_run`
- GitHub `deployment_status`
- GitLab `Pipeline Hook`
- GitLab `Deployment Hook`

Not V1:

- GitHub `check_run`
- GitLab `Job Hook`
- Jenkins
- CircleCI
- Provider API polling
- SHA -> PR -> issue tracing
- Background async processing
- Automatic retry jobs for failed provider events

V1 may call processors inline after storing `ExternalProviderEvent`. Failed events can be inspected through stored event status and error fields, but scheduled retry/replay is a later phase.

## Execution Order

1. WP1 Schema + Models
2. WP2 GitHub CI/CD Processors
3. WP3 GitLab CI/CD Processors
4. WP5 Automation + Settings
5. WP4 Development Panel UI
6. WP6 Tests + Regression Run

Do not start WP2 or WP3 until WP1 is complete.
Do not start WP4 until WP5 is complete because the panel UI depends on `show_builds` and `show_deployments` settings.

## WP1: Schema + Models

### Goal

Add persistent build and deployment records with issue join tables.

### Files To Add

- `plugins/redmine_dev_integration/db/migrate/007_create_external_builds_and_deployments.rb`
- `plugins/redmine_dev_integration/app/models/external_build.rb`
- `plugins/redmine_dev_integration/app/models/external_deployment.rb`
- `plugins/redmine_dev_integration/app/models/external_build_issue.rb`
- `plugins/redmine_dev_integration/app/models/external_deployment_issue.rb`
- `plugins/redmine_dev_integration/test/unit/external_build_test.rb`
- `plugins/redmine_dev_integration/test/unit/external_deployment_test.rb`

### ExternalBuild Fields

- `provider`
- `external_repository_id`
- `provider_build_id`
- `build_number`
- `name`
- `status`
- `conclusion`
- `url`
- `sha`
- `ref`
- `branch_name`
- `author_login`
- `started_at`
- `finished_at`
- `last_event_at`
- timestamps

### ExternalBuild Statuses

- `queued`
- `in_progress`
- `success`
- `failed`
- `canceled`
- `skipped`
- `unknown`

### ExternalDeployment Fields

- `provider`
- `external_repository_id`
- `provider_deployment_id`
- `environment_name`
- `environment_url`
- `status`
- `sha`
- `ref`
- `branch_name`
- `description`
- `creator_login`
- `started_at`
- `completed_at`
- `last_event_at`
- timestamps

### ExternalDeployment Statuses

- `pending`
- `in_progress`
- `success`
- `failed`
- `canceled`
- `rolled_back`
- `unknown`

### Indexes

- Build semantic dedup:
  - unique index on `provider`, `external_repository_id`, `provider_build_id`
- Deployment semantic dedup:
  - unique index on `provider`, `external_repository_id`, `provider_deployment_id`, `environment_name`
- Join tables:
  - unique index on `external_build_id`, `issue_id`
  - unique index on `external_deployment_id`, `issue_id`
  - index on `issue_id`

### Model Behavior

Mirror the existing branch/PR model style:

- `ExternalBuild belongs_to :external_repository`
- `ExternalBuild has_many :external_build_issues`
- `ExternalBuild has_many :issues, through: :external_build_issues`
- `ExternalDeployment belongs_to :external_repository`
- `ExternalDeployment has_many :external_deployment_issues`
- `ExternalDeployment has_many :issues, through: :external_deployment_issues`
- Validate required fields.
- Validate status inclusion.
- Add `link_issues_from_texts(*texts)` on both models.
- `link_issues_from_texts` must use `RedmineDevIntegration::IssueLinker`.
- Only link issues whose `project_id` matches `external_repository.redmine_project_id`.
- Multiple issue keys must create multiple join rows.
- Unknown keys must not raise.

### Acceptance Tests

- build validates status inclusion.
- deployment validates status inclusion.
- build dedup uniqueness prevents same provider/repo/provider_build_id.
- deployment dedup uniqueness prevents same provider/repo/provider_deployment_id/environment_name.
- build links issue from `feature/AUTH-1-login`.
- deployment links issue from `Deploy AUTH-1 to staging`.
- unknown issue key does not fail.

### Suggested Verification

```sh
bundle exec rake redmine:plugins:migrate RAILS_ENV=test
bundle exec rails test plugins/redmine_dev_integration/test/unit/external_build_test.rb plugins/redmine_dev_integration/test/unit/external_deployment_test.rb
```

## WP2: GitHub CI/CD Processors

### Goal

Process GitHub Actions and deployment webhooks into `ExternalBuild` and `ExternalDeployment`.

### Files To Add

- `plugins/redmine_dev_integration/lib/redmine_dev_integration/github_workflow_run_processor.rb`
- `plugins/redmine_dev_integration/lib/redmine_dev_integration/github_deployment_status_processor.rb`
- `plugins/redmine_dev_integration/test/unit/github_workflow_run_processor_test.rb`
- `plugins/redmine_dev_integration/test/unit/github_deployment_status_processor_test.rb`

### Files To Edit

- `plugins/redmine_dev_integration/lib/redmine_dev_integration/external_provider_event_processor.rb`

### Dispatch Rules

- `github_workflow_run_processor.call(event)` handles only:
  - `provider == "github"`
  - `event_type == "workflow_run"`
- `github_deployment_status_processor.call(event)` handles only:
  - `provider == "github"`
  - `event_type == "deployment_status"`
- Return `true` when handled, `false` when not applicable.

### Repository Lookup

Find `ExternalRepository` by:

- `provider: "github"`
- `provider_repository_id: payload["repository"]["id"].to_s`
- `active: true`

If missing, return `true` after safely no-op processing the event. Do not raise.

Reason: the dispatcher treats `true` as `processed`; in V1, an unmapped repository means the webhook was valid and understood, but there was no configured Redmine target to update.

### GitHub workflow_run Mapping

Payload source: `payload["workflow_run"]`.

ExternalBuild mapping:

- `provider`: `"github"`
- `external_repository`: matched repository
- `provider_build_id`: `workflow_run["id"].to_s`
- `build_number`: `workflow_run["run_number"]`
- `name`: `workflow_run["display_title"]` or `workflow_run["name"]` or `"Workflow run #{id}"`
- `status`: normalized GitHub workflow status
- `conclusion`: `workflow_run["conclusion"]`
- `url`: `workflow_run["html_url"]`
- `sha`: `workflow_run["head_sha"]`
- `ref`: `workflow_run["head_branch"]`
- `branch_name`: `workflow_run["head_branch"]`
- `author_login`: `workflow_run["actor"]["login"]`
- `started_at`: `workflow_run["run_started_at"]` or `workflow_run["created_at"]`
- `finished_at`: `workflow_run["updated_at"]` when completed
- `last_event_at`: `workflow_run["updated_at"]` or event creation time

Status mapping:

- `queued`, `requested`, `waiting` -> `queued`
- `in_progress` -> `in_progress`
- `completed` + `success` -> `success`
- `completed` + `failure` -> `failed`
- `completed` + `cancelled` or `canceled` -> `canceled`
- `completed` + `skipped` -> `skipped`
- else -> `unknown`

Issue link text sources:

- build name
- branch name
- ref
- `workflow_run["head_commit"]["message"]` when present

### GitHub deployment_status Mapping

Payload sources:

- `payload["deployment"]`
- `payload["deployment_status"]`

ExternalDeployment mapping:

- `provider`: `"github"`
- `external_repository`: matched repository
- `provider_deployment_id`: `deployment["id"].to_s`
- `environment_name`: `deployment["environment"]` or `deployment_status["environment"]` or `"unknown"`
- `environment_url`: `deployment_status["environment_url"]` or `deployment_status["target_url"]`
- `status`: normalized GitHub deployment status
- `sha`: `deployment["sha"]`
- `ref`: `deployment["ref"]`
- `branch_name`: `deployment["ref"]`
- `description`: `deployment_status["description"]` or `deployment["description"]`
- `creator_login`: `deployment_status["creator"]["login"]` or `deployment["creator"]["login"]`
- `started_at`: `deployment["created_at"]`
- `completed_at`: `deployment_status["created_at"]` when terminal
- `last_event_at`: `deployment_status["updated_at"]` or `deployment_status["created_at"]`

Status mapping:

- `pending`, `queued` -> `pending`
- `in_progress`, `waiting` -> `in_progress`
- `success` -> `success`
- `failure`, `error`, `failed` -> `failed`
- `cancelled`, `canceled`, `inactive` -> `canceled`
- else -> `unknown`

Issue link text sources:

- deployment ref
- deployment branch name
- deployment description
- environment URL

### Semantic Dedup

- Use `find_or_initialize_by(provider:, external_repository:, provider_build_id:)` for builds.
- Use `find_or_initialize_by(provider:, external_repository:, provider_deployment_id:, environment_name:)` for deployments.
- Same provider object with different webhook delivery ID updates the same record.

### Acceptance Tests

- GitHub `workflow_run` creates build.
- GitHub `workflow_run` updates existing build.
- GitHub `workflow_run` links issue by branch.
- duplicate `workflow_run` does not duplicate build.
- GitHub `deployment_status` creates deployment.
- GitHub `deployment_status` updates deployment status.
- GitHub deployment links issue by ref/description.
- unknown provider repo does not raise.

### Suggested Verification

```sh
bundle exec rails test plugins/redmine_dev_integration/test/unit/github_workflow_run_processor_test.rb plugins/redmine_dev_integration/test/unit/github_deployment_status_processor_test.rb plugins/redmine_dev_integration/test/unit/external_provider_event_processor_test.rb
```

## WP3: GitLab CI/CD Processors

### Goal

Process GitLab Pipeline and Deployment hooks into `ExternalBuild` and `ExternalDeployment`.

### Files To Add

- `plugins/redmine_dev_integration/lib/redmine_dev_integration/gitlab_pipeline_processor.rb`
- `plugins/redmine_dev_integration/lib/redmine_dev_integration/gitlab_deployment_processor.rb`
- `plugins/redmine_dev_integration/test/unit/gitlab_pipeline_processor_test.rb`
- `plugins/redmine_dev_integration/test/unit/gitlab_deployment_processor_test.rb`

### Files To Edit

- `plugins/redmine_dev_integration/lib/redmine_dev_integration/external_provider_event_processor.rb`

### Dispatch Rules

- `gitlab_pipeline_processor.call(event)` handles only:
  - `provider == "gitlab"`
  - `event_type == "Pipeline Hook"`
- `gitlab_deployment_processor.call(event)` handles only:
  - `provider == "gitlab"`
  - `event_type == "Deployment Hook"`
- Return `true` when handled, `false` when not applicable.

### Repository Lookup

Find `ExternalRepository` by:

- `provider: "gitlab"`
- `provider_repository_id: payload["project"]["id"].to_s`
- `active: true`

If missing, return `true` after safely no-op processing the event. Do not raise.

Reason: the dispatcher treats `true` as `processed`; in V1, an unmapped repository means the webhook was valid and understood, but there was no configured Redmine target to update.

### GitLab Pipeline Mapping

Payload source: `payload["object_attributes"]`.

ExternalBuild mapping:

- `provider`: `"gitlab"`
- `external_repository`: matched repository
- `provider_build_id`: `object_attributes["id"].to_s`
- `build_number`: `object_attributes["iid"]` or `object_attributes["id"]`
- `name`: `object_attributes["name"]` or `"Pipeline #{id}"`
- `status`: normalized GitLab pipeline status
- `conclusion`: `object_attributes["status"]`
- `url`: `object_attributes["url"]`
- `sha`: `object_attributes["sha"]`
- `ref`: `object_attributes["ref"]`
- `branch_name`: `object_attributes["ref"]`
- `author_login`: `payload["user"]["username"]` or `payload["user"]["name"]`
- `started_at`: `object_attributes["created_at"]`
- `finished_at`: `object_attributes["finished_at"]`
- `last_event_at`: `object_attributes["updated_at"]` or `object_attributes["finished_at"]`

Status mapping:

- `created`, `pending` -> `queued`
- `running` -> `in_progress`
- `success` -> `success`
- `failed` -> `failed`
- `canceled`, `cancelled` -> `canceled`
- `skipped` -> `skipped`
- else -> `unknown`

Issue link text sources:

- build name
- ref
- branch name
- `payload["commit"]["message"]`
- `payload["commit"]["title"]`

### GitLab Deployment Mapping

ExternalDeployment mapping:

- `provider`: `"gitlab"`
- `external_repository`: matched repository
- `provider_deployment_id`: `payload["deployment_id"]` or `payload["id"]`
- `environment_name`: `payload["environment"]` or `"unknown"`
- `environment_url`: `payload["environment_external_url"]`
- `status`: normalized GitLab deployment status
- `sha`: `payload["sha"]`
- `ref`: `payload["ref"]`
- `branch_name`: `payload["ref"]`
- `description`: `payload["commit_title"]` or `payload["status"]`
- `creator_login`: `payload["user"]["username"]` or `payload["user"]["name"]`
- `started_at`: `payload["deployable_started_at"]` or `payload["created_at"]`
- `completed_at`: `payload["deployable_finished_at"]` or `payload["updated_at"]` when terminal
- `last_event_at`: `payload["updated_at"]` or `payload["deployable_finished_at"]`

Status mapping:

- `created`, `pending`, `blocked` -> `pending`
- `running` -> `in_progress`
- `success` -> `success`
- `failed` -> `failed`
- `canceled`, `cancelled` -> `canceled`
- else -> `unknown`

Issue link text sources:

- ref
- branch name
- deployment description
- environment URL

### Semantic Dedup

- Use `find_or_initialize_by(provider:, external_repository:, provider_build_id:)` for builds.
- Use `find_or_initialize_by(provider:, external_repository:, provider_deployment_id:, environment_name:)` for deployments.

### Acceptance Tests

- GitLab `Pipeline Hook` creates build.
- GitLab `Pipeline Hook` updates existing build.
- GitLab pipeline links issue by ref.
- GitLab `Deployment Hook` creates deployment.
- GitLab deployment links issue by ref.
- unknown provider repo does not raise.

### Suggested Verification

```sh
bundle exec rails test plugins/redmine_dev_integration/test/unit/gitlab_pipeline_processor_test.rb plugins/redmine_dev_integration/test/unit/gitlab_deployment_processor_test.rb plugins/redmine_dev_integration/test/unit/external_provider_event_processor_test.rb
```

## WP4: Development Panel UI

### Goal

Show linked builds and deployments in the existing issue Development tab.

### Files To Edit

- `plugins/redmine_dev_integration/lib/redmine_dev_integration/issue_development_panel_data.rb`
- `plugins/redmine_dev_integration/app/views/issues/tabs/_development.html.erb`
- `plugins/redmine_dev_integration/config/locales/en.yml`
- `plugins/redmine_dev_integration/test/unit/issue_development_panel_data_test.rb`
- `plugins/redmine_dev_integration/test/functional/issues_controller_patch_test.rb`

### Panel Data

Add methods:

- `builds`
- `deployments`

Query pattern:

- include `external_repository`
- join the relevant issue join table
- filter by current `issue.id`
- filter repository project to `issue.project_id`
- order newest first by `last_event_at`, then `updated_at`

### Visibility

Respect project settings:

- `show_dev_panel == false` hides the whole tab already.
- Add `show_builds` for Builds section.
- Add `show_deployments` for Deployments section.

If settings row is missing, default:

- `show_builds = true`
- `show_deployments = true`

### Build Row

Show:

- name
- status
- branch/ref
- short SHA
- provider and repository full name
- started/finished time
- external URL

### Deployment Row

Show:

- environment name
- status
- branch/ref
- short SHA
- provider and repository full name
- completed time
- environment URL

### Empty State

- Keep existing Redmine-style `<p class="nodata">`.
- Either hide a section when disabled or show no-data when enabled but empty.

### Acceptance Tests

- issue with linked build exposes build from panel data.
- issue with linked deployment exposes deployment from panel data.
- Builds section renders when builds exist.
- Deployments section renders when deployments exist.
- sections hidden when project settings disable them.

### Suggested Verification

```sh
bundle exec rails test plugins/redmine_dev_integration/test/unit/issue_development_panel_data_test.rb plugins/redmine_dev_integration/test/functional/issues_controller_patch_test.rb
```

## WP5: Automation + Settings

### Goal

Add optional project-level automation and visibility settings for build/deployment events.

### Files To Add

- `plugins/redmine_dev_integration/db/migrate/008_add_build_deployment_settings_to_development_integration_project_settings.rb`

### Files To Edit

- `plugins/redmine_dev_integration/app/models/development_integration_project_setting.rb`
- `plugins/redmine_dev_integration/app/controllers/projects/redmine_dev_integration_controller.rb`
- `plugins/redmine_dev_integration/app/views/projects/settings/_redmine_dev_integration.html.erb`
- `plugins/redmine_dev_integration/config/locales/en.yml`
- `plugins/redmine_dev_integration/lib/redmine_dev_integration/automation_service.rb`
- processor files from WP2/WP3 to call automation
- `plugins/redmine_dev_integration/test/unit/automation_service_test.rb`
- `plugins/redmine_dev_integration/test/unit/development_integration_project_setting_test.rb`
- `plugins/redmine_dev_integration/test/functional/projects/redmine_dev_integration_controller_test.rb`
- `plugins/redmine_dev_integration/test/unit/redmine_dev_integration_partial_test.rb`

### Settings Fields

Add to `development_integration_project_settings`:

- `show_builds`, boolean, default true, not null
- `show_deployments`, boolean, default true, not null
- `build_failed_note_enabled`, boolean, default false, not null
- `build_success_status_id`, nullable issue status reference
- `deployment_staging_success_status_id`, nullable issue status reference
- `deployment_production_success_status_id`, nullable issue status reference
- `deployment_failed_note_enabled`, boolean, default false, not null
- `deployment_failed_status_id`, nullable issue status reference

### Model Updates

- Add optional `belongs_to` associations for all status IDs.
- Validate all booleans in `[true, false]`.
- `after_initialize` should default booleans:
  - `show_builds = true`
  - `show_deployments = true`
  - note booleans false

### Automation Event Types

Add:

- `build_failed`
- `build_success`
- `deployment_staging_success`
- `deployment_production_success`
- `deployment_failed`

### Automation Behavior

- Automation still requires `automation_enabled == true`.
- `build_failed` adds a note only when `build_failed_note_enabled == true`.
- `build_success` changes status only when `build_success_status_id` is present.
- `deployment_staging_success` changes status only when mapped status is present.
- `deployment_production_success` changes status only when mapped status is present.
- `deployment_failed` adds a note when `deployment_failed_note_enabled == true`.
- `deployment_failed` also changes status when `deployment_failed_status_id` is present.
- Every note/status change must use marker-based dedup.
- Repeated webhook must not duplicate journal entries.

### Processor Integration

After linking issues:

- For each linked issue, call automation using a stable marker.
- Suggested build marker:
  - `build:<provider>:<external_build.id>:<event_type>`
- Suggested deployment marker:
  - `deployment:<provider>:<external_deployment.id>:<event_type>`
- If automation returns skipped and a plain audit note is desired, use `AuditNoteService` with a different stable marker.
- Do not create duplicate notes from both automation and audit service for the same event.

### Acceptance Tests

- automation disabled by default.
- failed build does not change issue status when disabled.
- failed build adds one note when enabled and note setting is true.
- repeated failed build does not duplicate the note.
- build success maps issue to configured status.
- production deployment success maps issue to configured status.
- deployment failure note dedups.
- blank mappings mean no status change.

### Suggested Verification

```sh
bundle exec rails test plugins/redmine_dev_integration/test/unit/automation_service_test.rb plugins/redmine_dev_integration/test/unit/development_integration_project_setting_test.rb plugins/redmine_dev_integration/test/functional/projects/redmine_dev_integration_controller_test.rb plugins/redmine_dev_integration/test/unit/redmine_dev_integration_partial_test.rb
```

## WP6: Tests + Regression Run

### Goal

Complete test coverage and verify existing plugin behavior still passes.

### Required Test Matrix

- GitHub `workflow_run` creates build.
- GitHub `workflow_run` updates existing build.
- GitHub `workflow_run` links issue by branch.
- GitHub `workflow_run` duplicate does not duplicate build.
- GitHub `deployment_status` creates deployment.
- GitHub `deployment_status` updates deployment status.
- GitHub deployment links issue by ref/description.
- GitLab `Pipeline Hook` creates build.
- GitLab `Pipeline Hook` updates existing build.
- GitLab pipeline links issue by ref.
- GitLab `Deployment Hook` creates deployment.
- GitLab deployment links issue.
- Build appears in Development tab.
- Deployment appears in Development tab.
- Automation disabled by default.
- Build failed note dedup works.
- Deployment success status mapping works.
- Unknown issue key does not fail processing.
- Unknown provider repo stores/ignores safely.
- Invalid GitHub webhook signature rejected.
- Invalid GitLab token rejected.
- Existing branch processor tests still pass.
- Existing PR/MR processor tests still pass.

### Full Verification

```sh
bundle exec rake redmine:plugins:migrate RAILS_ENV=test
bundle exec rails test plugins/redmine_dev_integration/test
```

If tests fail due to browser/system sandboxing, run only plugin unit/functional tests first and report the system-test blocker separately.

## Subagent Prompt Templates

### WP1 Prompt

Implement WP1 from `plugins/redmine_dev_integration/build_deployment_execution_breakdown.md`. Only add schema/models/tests for ExternalBuild and ExternalDeployment. Do not implement processors or UI. Preserve existing plugin behavior. Run the WP1 verification command and report changed files and test results.

### WP2 Prompt

Implement WP2 from `plugins/redmine_dev_integration/build_deployment_execution_breakdown.md`. Assume WP1 is complete. Add GitHub workflow_run and deployment_status processors, update event dispatch, and add focused tests. Do not implement GitLab, UI, or automation beyond linking records to issues. Run the WP2 verification command and report changed files and test results.

### WP3 Prompt

Implement WP3 from `plugins/redmine_dev_integration/build_deployment_execution_breakdown.md`. Assume WP1 is complete. Add GitLab Pipeline Hook and Deployment Hook processors, update event dispatch, and add focused tests. Do not implement GitHub, UI, or automation beyond linking records to issues. Run the WP3 verification command and report changed files and test results.

### WP4 Prompt

Implement WP4 from `plugins/redmine_dev_integration/build_deployment_execution_breakdown.md`. Assume WP1 is complete and processors may already create linked records. Extend panel data and the existing Development tab partial to show Builds and Deployments, respecting visibility settings. Do not override core views. Run the WP4 verification command and report changed files and test results.

### WP5 Prompt

Implement WP5 from `plugins/redmine_dev_integration/build_deployment_execution_breakdown.md`. Add project settings and automation for build/deployment events. Keep automation disabled by default and journal changes deduped with markers. Run the WP5 verification command and report changed files and test results.

### WP6 Prompt

Implement WP6 from `plugins/redmine_dev_integration/build_deployment_execution_breakdown.md`. Fill missing tests from the required matrix, run full dev integration tests, and fix regressions. Do not add new features beyond the requirements. Report remaining gaps if any.

## Final Definition Of Done

- GitHub `workflow_run` visible on linked issue.
- GitHub `deployment_status` visible on linked issue.
- GitLab `Pipeline Hook` visible on linked issue.
- GitLab `Deployment Hook` visible on linked issue.
- Duplicate webhooks do not duplicate build/deployment records.
- Duplicate webhooks do not duplicate notes/status journals.
- Automation remains disabled by default.
- Builds/deployments are hidden when project settings disable them.
- No core view override added.
- Existing branches, PR/MR, commit panel, webhooks, and automation tests still pass.
