# Redmine Dev Integration

Connects Redmine to GitHub, GitLab, and Bitbucket for end-to-end development workflow visibility and automation.

---

## Table of Contents

1. [Features](#features)
2. [Installation](#installation)
3. [Quick Start](#quick-start)
4. [Configuration](#configuration)
5. [Webhook Setup](#webhook-setup)
6. [OAuth Setup](#oauth-setup)
7. [Automation](#automation)
8. [Smart Commits](#smart-commits)
9. [Reconciliation](#reconciliation)
10. [User Identity Mapping](#user-identity-mapping)
11. [Deployment Overview](#deployment-overview)
12. [Database Schema](#database-schema)
13. [Permissions](#permissions)
14. [Architecture](#architecture)
15. [Troubleshooting](#troubleshooting)
16. [Known Limitations](#known-limitations)
17. [Running Tests](#running-tests)
18. [Integration with redmine_issue_keys](#integration-with-redmine_issue_keys)

---

## Features

### Development Panel on Issues
- Displays linked branches, pull requests / merge requests, external commits, SCM changesets, builds, and deployments
- Native Redmine journal-style rendering — zero custom CSS
- Provider links open with external link icons
- Per-project show/hide toggles for builds and deployments

### Multi-Provider Webhook Processing

| Provider | Events |
|---|---|
| **GitHub** | `push`, `pull_request`, `workflow_run`, `deployment_status`, `create` |
| **GitLab** | `Push Hook`, `Merge Request Hook`, `Pipeline Hook`, `Deployment Hook` |
| **Bitbucket** | `repo:push`, `pullrequest:*`, `repo:commit_status_*`, `repo:deployment` |

- HMAC-SHA256 signature verification (GitHub), token verification (GitLab), HMAC verification (Bitbucket)
- Delivery-ID-based deduplication prevents double-processing
- Async processing via ActiveJob (`ExternalProviderEventJob`)
- Failed events can be retried from the project UI
- Provider enable/disable toggle per global settings

### Smart Commits

Commands parsed from commit messages in push webhooks:

| Command | Action |
|---|---|
| `PROJ-123 #comment Fixed the bug` | Adds journal note |
| `PROJ-123 #done` | Transitions to PR merged status |
| `PROJ-123 #in-progress` | Transitions to PR merged status |
| `PROJ-123 #resolve` | Transitions to PR merged status |
| `PROJ-123 #time 2h 30m` | Logs time entry (hours parsed from `{N}h {N}m` format) |
| `PROJ-123 #assign admin` | Assigns to Redmine user by login |

- Multiple commands per commit, multiple issue keys per commit
- Case-insensitive matching
- Dedup marker prevents duplicate execution per commit SHA
- Resolves committer to Redmine user via `ProviderUserResolver`
- Per-project enable toggle
- Requires `redmine_issue_keys` companion plugin

### Automation Engine

Two-tier system:

**1. Legacy status mappings** — 10 event types mapped directly to issue statuses in project settings:

| Event | Action |
|---|---|
| Branch created | Set status |
| PR opened | Set status |
| PR merged | Set status |
| PR closed without merge | Add note |
| Build failed | Add note |
| Build success | Set status |
| Deployment staging success | Set status |
| Deployment production success | Set status |
| Deployment failed | Set status + optional note |

**2. Custom automation rules** (`DevelopmentIntegrationAutomationRule`) — 5 action types:

| Action | Description |
|---|---|
| `assign_user` | Assign issue to a Redmine user by login |
| `set_priority` | Change issue priority by name |
| `set_custom_field` | Set issue custom field value (`{field_id}:{value}`) |
| `change_status` | Transition to any issue status by name |
| `add_note` | Add journal note |

Rules are per-project, per-event-type, and optionally per-environment. Strong deduplication via `ExternalAutomationEvent` markers prevents re-play on duplicate webhook deliveries.

**3. Environment rules** (`DevelopmentIntegrationEnvironmentRule`) — per-environment deployment automation for any environment name (not just staging/production).

### Data Tracking

| Model | Table | Purpose |
|---|---|---|
| `ExternalRepository` | `external_repositories` | Provider connection: provider, repo ID, owner, name, URL, active flag |
| `ExternalBranch` | `external_branches` | Branch: name, SHA, state (active/deleted), soft-delete support |
| `ExternalCommit` | `external_commits` | Commit: SHA, short_sha, message, author, branch, URL, timestamp |
| `ExternalPullRequest` | `external_pull_requests` | PR/MR: number, title, body, URL, state, merged, source/target branch, SHAs, timestamps |
| `ExternalBuild` | `external_builds` | CI build: provider build ID, number, name, status, conclusion, URL, SHA, branch |
| `ExternalDeployment` | `external_deployments` | Deployment: provider ID, environment, status, SHA, ref, creator, timestamps |
| `ExternalProviderEvent` | `external_provider_events` | Webhook event journal: provider, delivery ID, event type, payload, status |
| `ExternalAutomationEvent` | `external_automation_events` | Dedup marker: issue ID + marker + action type |
| `ExternalProviderUserMapping` | `external_provider_user_mappings` | Provider user → Redmine user mapping |
| `DevelopmentIntegrationProjectSetting` | `development_integration_project_settings` | Per-project configuration: toggles, status mappings |
| `DevelopmentIntegrationAutomationRule` | `development_integration_automation_rules` | Custom automation rules |
| `DevelopmentIntegrationEnvironmentRule` | `development_integration_environment_rules` | Per-environment deployment rules |

All junction tables use unique composite indexes for deduplication:
`external_branch_issues`, `external_commit_issues`, `external_pull_request_issues`, `external_build_issues`, `external_deployment_issues`

### Issue Linking

- Scans branch names, commit messages, PR/MR titles/bodies, build names/refs, deployment refs for issue key patterns (`[A-Z][A-Z0-9]{1,15}-\d+`)
- SHA tracing fallback: if no issue key found in build/deployment metadata, traces the SHA to known PR/MR → issue links (local DB lookup, no external API call)
- `IssueLinker` bridges `IssueKeyExtractor` regex to `Issue.find_by_issue_key` from companion plugin
- Graceful degradation when `redmine_issue_keys` is not installed — records are stored, linking is skipped, no errors raised

### Deployment Overview

- Full dedicated page: `GET /projects/:id/deployment_overview`
- Latest deployment per environment with status, repository, branch/ref, SHA, linked issues, completed timestamp, provider URL
- Permission-gated (`view_development_integration`)

### Repository Management

- **4-tab project settings**: Development Settings, Repositories, Provider Events, User Mappings
- Separate new/edit repository pages (Redmine-native pattern — no inline forms)
- Provider repository URL parsing: HTTPS URLs, SSH URLs (`git@github.com:owner/repo.git`), plain `owner/repo` format
- Optional SCM repository linking (layered on top, not replacing Redmine SCM)
- Soft deactivation preserves all historical data; reactivation restores full functionality
- One-click webhook registration via provider API (creates webhook on GitHub/GitLab/Bitbucket)
- Repository auto-populate from provider API when OAuth is connected (lists user's repos)
- Auto webhook registration on repository creation (per-project toggle)

### Reconciliation

- Manual: project UI → Repositories tab → click reconcile icon
- Rake tasks for cron scheduling
- Auto-reconciliation: request-triggered background check every 15 minutes
- Fetches recent PRs/MRs, builds, deployments from provider API (paginated, up to 500 items)
- Upsert with semantic deduplication keys
- Distributed lock via `Rails.cache` prevents concurrent runs across multiple processes
- Skips inactive repositories and disabled providers gracefully

### Authentication

- **GitHub OAuth**: OAuth2 web flow, `repo` + `admin:repo_hook` scopes, encrypted token storage
- **GitLab OAuth**: OAuth2 web flow, `api` scope, supports self-hosted via base URL setting
- **Bitbucket OAuth**: OAuth2 web flow, consumer key/secret, encrypted token storage
- **PAT fallback**: Personal access tokens for all three providers when OAuth not configured
- OAuth tokens preferred over PATs when both are present
- All tokens encrypted at rest via `ActiveSupport::MessageEncryptor` (AES-256-GCM, key derived from Rails `secret_key_base`)
- Empty form submissions preserve existing secrets (no accidental credential loss)

### User Identity Mapping

- Map provider usernames to Redmine users (global, applies to all projects)
- `ProviderUserResolver.with_resolved_user` wraps webhook processing with correct user context
- Journal entries and automation notes attributed to the mapped Redmine user

---

## Installation

```sh
# From Redmine root:
bundle exec rake redmine:plugins:migrate NAME=redmine_dev_integration RAILS_ENV=production
```

**Requirements:**
- Redmine >= 6.0.0
- Ruby >= 3.2.0
- ActiveJob backend configured (default: async; recommended: Sidekiq or similar for production)

**Companion plugin strongly recommended:**
```sh
bundle exec rake redmine:plugins:migrate NAME=redmine_issue_keys RAILS_ENV=production
```

Without `redmine_issue_keys`, all records are created and stored, but issue linking via webhook data will not work. No errors are raised — linking gracefully returns empty results.

---

## Quick Start

1. Install both plugins and run migrations
2. Go to **Administration → Plugins → Redmine Dev Integration → Configure**
3. Enable GitHub (and/or GitLab, Bitbucket) and configure webhook secrets
4. Optionally configure OAuth for one-click repo listing
5. Go to **Project → Settings → Redmine Dev Integration**
6. On the **Development Settings** tab: check "Show development panel", save
7. On the **Repositories** tab: add a repository (provider, URL/path, provider repository ID)
8. Register a webhook on the repository row
9. Push a branch or open a PR referencing an issue key — see it on the issue's **Development** tab

---

## Configuration

### Global Plugin Settings

**Path:** Administration → Plugins → Redmine Dev Integration → Configure

**GitHub section:**
| Field | Purpose |
|---|---|
| Accept GitHub webhooks | Master toggle — disable to reject all incoming GitHub webhooks |
| Webhook signing secret | HMAC-SHA256 secret for signature verification |
| API token | Personal access token for reconciliation API calls |
| OAuth Client ID / Secret | OAuth2 app credentials |
| Connect / Disconnect | One-click OAuth authorization flow |

**GitLab section:**
| Field | Purpose |
|---|---|
| Accept GitLab webhooks | Master toggle |
| Webhook secret token | Static token for webhook verification |
| API token | Personal access token for reconciliation |
| GitLab base URL | Only needed for self-hosted GitLab (default: `https://gitlab.com`) |
| OAuth App ID / Secret | OAuth2 app credentials |
| Connect / Disconnect | One-click OAuth authorization |

**Bitbucket section:**
| Field | Purpose |
|---|---|
| Accept Bitbucket webhooks | Master toggle |
| Webhook signing secret | HMAC secret for webhook verification |
| API token | App password for reconciliation |
| OAuth Key / Secret | OAuth2 consumer credentials |
| Connect / Disconnect | One-click OAuth authorization |

### Per-Project Settings

**Path:** Project → Settings → Redmine Dev Integration

**Development Settings tab:**
| Setting | Default | Description |
|---|---|---|
| Show development panel | ✓ | Renders Development tab on issue pages |
| Enable automation | ✗ | Enables status changes and notes for webhook events |
| Auto-register webhooks | ✗ | Automatically creates webhooks on provider when adding a repository |
| Enable smart commits | ✗ | Parses `#comment`, `#done`, `#time`, `#assign` from commit messages |

**Branch / PR Automation:** status mappings for branch created, PR opened, PR merged, and PR closed without merge note toggle.

**Build / Deployment Automation:** show/hide toggles for builds and deployments, status mappings for build success, deployment staging/production success, deployment failed, and note toggles for build failure and deployment failure.

**Repositories tab:**
- List of connected external repositories with provider, URL, status, webhook registration
- Add new repository (separate page with form)
- Edit repository (separate page)
- Deactivate repository (soft-delete with confirmation dialog)
- Reconcile now (manual sync from provider API)
- Register webhook (creates webhook on provider via API)

**Provider Events tab:**
- Recent webhook delivery log filtered to the project's repositories
- Status: pending, processed, failed, ignored
- Retry button for failed events

**User Mappings tab:**
- List of provider user → Redmine user mappings (global)
- Add/delete mappings

---

## Webhook Setup

You can register webhooks from the project settings **Repositories** tab (click the reload icon on a repository row), or manually via the provider's UI.

### GitHub

1. Repository Settings → Webhooks → Add webhook
2. Payload URL: `https://your-redmine.example.com/dev_integrations/github/webhook`
3. Content type: `application/json`
4. Secret: same as `github_webhook_secret` in plugin settings
5. Events: **Send me everything** (push, pull request, workflow runs, deployment statuses)
6. Ensure **Active** is checked

### GitLab

1. Repository Settings → Webhooks
2. URL: `https://your-redmine.example.com/dev_integrations/gitlab/webhook`
3. Secret token: same as `gitlab_webhook_token` in plugin settings
4. Triggers: Push events, Merge request events, Pipeline events, Deployment events
5. Ensure **Enable SSL verification** is checked (unless using self-signed certs)

### Bitbucket

1. Repository Settings → Webhooks → Add webhook
2. Title: "Redmine Dev Integration"
3. URL: `https://your-redmine.example.com/dev_integrations/bitbucket/webhook`
4. Events: Push, Pull request (created, updated, fulfilled, rejected), Deployment
5. Secret: same as `bitbucket_webhook_secret` in plugin settings

### Webhook Processing Flow

```
POST /dev_integrations/{provider}/webhook
  → Verify signature/token (401 if invalid)
  → Check provider enabled (403 if disabled)
  → Deduplicate by delivery_id (200 if duplicate)
  → Store ExternalProviderEvent (status: pending)
  → Enqueue ExternalProviderEventJob (async)
  → Return 202 Accepted

ExternalProviderEventJob:
  → Acquire row lock (prevents concurrent processing)
  → Dispatch to provider-specific processor chain
  → GitHub: push_branch → pull_request → workflow_run → deployment_status
  → GitLab: push_branch → merge_request → pipeline → deployment
  → Bitbucket: push_branch → pull_request → pipeline → deployment
  → Mark event: processed | ignored | failed
  → Log structured JSON to Rails log
```

---

## OAuth Setup

### GitHub

1. Go to https://github.com/settings/developers
2. Register a new OAuth App
3. Application name: "Redmine Dev Integration"
4. Homepage URL: `https://your-redmine.example.com`
5. Authorization callback URL: `https://your-redmine.example.com/dev_integrations/github/oauth/callback`
6. Copy **Client ID** and generate a **Client Secret**
7. In Redmine: Administration → Plugins → Redmine Dev Integration → Configure
8. Paste Client ID and Client Secret in the GitHub OAuth section
9. Click **Connect GitHub** — you'll be redirected to GitHub to authorize
10. Required scopes: `repo`, `admin:repo_hook`

### GitLab

1. Go to https://gitlab.com/-/user_settings/applications (or your self-hosted instance: Admin → Applications)
2. Name: "Redmine Dev Integration"
3. Redirect URI: `https://your-redmine.example.com/dev_integrations/gitlab/oauth/callback`
4. Scopes: `api`
5. Copy **Application ID** and **Secret**
6. In Redmine plugin settings:
   - Paste Application ID and Secret
   - For self-hosted GitLab: set **GitLab base URL** (e.g., `https://gitlab.example.com`)
7. Click **Connect GitLab**

### Bitbucket

1. Go to Bitbucket → Workspace Settings → OAuth consumers → Add consumer
2. Name: "Redmine Dev Integration"
3. Callback URL: `https://your-redmine.example.com/dev_integrations/bitbucket/oauth/callback`
4. Permissions: Repositories (Read), Webhooks (Read and Write)
5. Copy **Key** and **Secret**
6. In Redmine plugin settings, paste Key and Secret
7. Click **Connect Bitbucket**

### Token Storage

All OAuth tokens are encrypted at rest using `ActiveSupport::MessageEncryptor` (AES-256-GCM). The encryption key is derived from `Rails.application.secret_key_base` using `ActiveSupport::KeyGenerator`.

- **Empty form submissions**: Preserve existing tokens — submitting an empty password field does NOT clear the stored credential
- **PAT fallback**: When both OAuth and PAT are configured, the OAuth token is preferred
- **Migration**: You can add OAuth alongside existing PATs — both work, OAuth is preferred
- **Expiry**: `expires_in` from the provider's token response is stored; tokens that expire will fall back to PAT

### Callback URLs Reference

| Provider | Path |
|---|---|
| GitHub | `/dev_integrations/github/oauth/callback` |
| GitLab | `/dev_integrations/gitlab/oauth/callback` |
| Bitbucket | `/dev_integrations/bitbucket/oauth/callback` |

---

## Automation

### How Automation Works

```
Webhook received → Event processed → Issue linked
  → AutomationService.call(issue, event_type, project)
    → Check: automation enabled for project?
    → Check: duplicate marker? (ExternalAutomationEvent)
    → Execute legacy status mapping OR custom automation rule
    → Create dedup marker
    → Add journal note with marker token
```

Automation is **disabled by default** per project. Enable it on the Development Settings tab.

### Legacy Status Mappings

Simple 1:1 mappings from event type to issue status. Configured in project settings under Branch/PR Automation and Build/Deployment Automation.

### Custom Automation Rules

More flexible rules stored in `development_integration_automation_rules`:

```ruby
DevelopmentIntegrationAutomationRule.create!(
  project: project,
  event_type: 'pr_opened',      # which event triggers this rule
  action_type: 'assign_user',   # what to do
  action_value: 'admin',        # parameter for the action
  active: true
)
```

| Event Type | Available Actions |
|---|---|
| `branch_created` | assign_user, set_priority, set_custom_field, change_status, add_note |
| `pr_opened` | assign_user, set_priority, set_custom_field, change_status, add_note |
| `pr_merged` | assign_user, set_priority, set_custom_field, change_status, add_note |
| `build_success` | assign_user, set_priority, set_custom_field, change_status, add_note |
| `build_failed` | assign_user, set_priority, set_custom_field, change_status, add_note |
| `deployment_success` | assign_user, set_priority, set_custom_field, change_status, add_note |
| `deployment_failed` | assign_user, set_priority, set_custom_field, change_status, add_note |

Multiple rules can fire for the same event. Rules execute in `created_at` order.

### Environment Rules

Per-environment deployment automation stored in `development_integration_environment_rules`:

```ruby
DevelopmentIntegrationEnvironmentRule.create!(
  project: project,
  environment_name: 'staging',
  success_status_id: some_status.id,
  failed_status_id: another_status.id,
  failed_note_enabled: true,
  active: true
)
```

Environment rules take precedence over legacy deployment status mappings. If both a legacy staging status AND an environment rule for "staging" exist, the environment rule is used.

### Deduplication

Every automation action creates an `ExternalAutomationEvent` record with a unique `[issue_id, marker]` composite key. Subsequent webhook deliveries, manual retries, or reconciliation re-processing the same event will detect the duplicate marker and skip the action.

Journal notes include the marker token for human auditability:
```
[redmine-dev-integration:github:pr:42:pr_opened:101]
PR opened: #42 | https://github.com/owner/repo/pull/42
```

---

## Smart Commits

Smart commits are parsed from push webhook commit messages. They require `redmine_issue_keys` for issue key resolution.

### Syntax

```
PROJ-123 #comment The login bug is now fixed
PROJ-123 #done
PROJ-123 #time 1h 30m
PROJ-123 #assign jsmith
PROJ-123 #done #time 2h
PROJ-123 #comment Fixed #assign jsmith #done
```

### Command Reference

| Command | What it does | Example |
|---|---|---|
| `#comment <text>` | Adds journal note | `PROJ-123 #comment Fixed the login bug` |
| `#done` | Transitions to PR merged status | `PROJ-123 #done` |
| `#in-progress` | Same as `#done` | `PROJ-123 #in-progress` |
| `#resolve` | Same as `#done` | `PROJ-123 #resolve` |
| `#time {N}h {N}m` | Logs time entry | `PROJ-123 #time 2h 30m` |
| `#assign <login>` | Assigns issue | `PROJ-123 #assign admin` |

### Limitations

- `#done`, `#in-progress`, and `#resolve` all map to the same "PR merged" status — there is no distinct "in-progress" transition
- Time format supports `{N}h` and `{N}m` suffixes (e.g., `2h 30m`, `1.5h`, `45m`). Only hours are stored (minutes converted to decimal)
- Commands are case-insensitive
- The committer is resolved to a Redmine user via `ProviderUserResolver`; if no mapping exists, `User.current` is used

---

## Reconciliation

### Manual

Project → Settings → Repositories tab → click the reload icon on a repository row.

### Rake Tasks

```sh
# Reconcile all active repositories
bundle exec rake redmine_dev_integration:reconcile_all RAILS_ENV=production

# Reconcile only GitHub repos
PROVIDER=github bundle exec rake redmine_dev_integration:reconcile_all RAILS_ENV=production

# Reconcile a single project
PROJECT=myproject bundle exec rake redmine_dev_integration:reconcile_project RAILS_ENV=production

# Preview which repos would be reconciled (no changes)
DRY_RUN=1 bundle exec rake redmine_dev_integration:reconcile_all RAILS_ENV=production
```

### Cron Scheduling

```sh
# Every 5 minutes: reconcile all active repositories
*/5 * * * * cd /path/to/redmine && bundle exec rake redmine_dev_integration:reconcile_all RAILS_ENV=production >> log/reconciliation.log 2>&1

# Every 10 minutes: GitHub only
*/10 * * * * cd /path/to/redmine && PROVIDER=github bundle exec rake redmine_dev_integration:reconcile_all RAILS_ENV=production >> log/reconciliation.log 2>&1

# Hourly: specific project
0 * * * * cd /path/to/redmine && PROJECT=myproject bundle exec rake redmine_dev_integration:reconcile_project RAILS_ENV=production >> log/reconciliation.log 2>&1
```

### Auto-Reconciliation (Request-Triggered)

The plugin checks once every 15 minutes (on any incoming request) whether any repository is due for reconciliation:

- Uses `Rails.cache` distributed lock (30-second TTL) to prevent concurrent runs
- Logs results to Rails logger: `[ScheduledReconciliation] Reconciled repo ...`
- One repository failure does not stop the run
- Provider-disabled and inactive repositories are skipped
- `DRY_RUN=1` on the rake task outputs a preview without making changes
- No external gem dependency — uses built-in Rails cache and notifications

### Reconciliation API Limits

| Provider | Per Page | Max Pages | Max Items |
|---|---|---|---|
| GitHub | 100 | 5 | 500 |
| GitLab | 100 | 5 | 500 |
| Bitbucket | 100 | 5 | 500 |

The reconciliation uses paginated API calls with Link-header parsing (GitHub) and X-Next-Page (GitLab) support. Records are upserted with provider-specific deduplication keys. `last_synced_at` is updated only after a successful full reconciliation within a transaction.

---

## Database Schema

### Core Tables

**`external_repositories`** — Provider repository connections

| Column | Type | Notes |
|---|---|---|
| `provider` | string | `github`, `gitlab`, or `bitbucket` |
| `provider_repository_id` | string | Immutable provider ID (numeric for GitHub/GitLab, UUID for Bitbucket) |
| `owner` | string | Owner/org/workspace name |
| `repo_name` | string | Repository name |
| `full_name` | string | `owner/repo_name` format |
| `url` | string | Canonical HTTPS URL |
| `redmine_project_id` | integer | FK to projects |
| `redmine_repository_id` | integer | Optional FK to Redmine SCM repository |
| `active` | boolean | Soft deactivation toggle |
| `provider_webhook_id` | string | The provider's webhook ID after registration |
| `webhook_registration_status` | string | `registered`, `not_registered`, `error` |
| `last_synced_at` | datetime | Updated on successful reconciliation |
| Unique index | `[provider, provider_repository_id]` | |

**`external_branches`** — Branch tracking

| Column | Notes |
|---|---|
| `external_repository_id` | FK |
| `name` | Branch name (without `refs/heads/`) |
| `url` | Provider URL to browse the branch |
| `sha` | Latest commit SHA |
| `state` | `active` or `deleted` |
| `deleted_at` | Set on soft-delete, cleared on re-activation |
| Unique index | `[external_repository_id, name]` |

**`external_commits`** — Per-commit tracking

| Column | Notes |
|---|---|
| `external_repository_id` | FK |
| `provider` | `github`, `gitlab`, or `bitbucket` |
| `provider_commit_id` | The provider's commit SHA |
| `sha` | Full SHA |
| `short_sha` | First 7 characters |
| `message` | Commit message |
| `author_login` | Provider username |
| `author_name` | Display name |
| `url` | Provider URL to the commit |
| `branch_name` | Branch this commit was pushed to |
| `committed_at` | Timestamp |
| Unique index | `[provider, external_repository_id, provider_commit_id]` |

**`external_pull_requests`** — PRs and MRs

| Column | Notes |
|---|---|
| `provider` | `github`, `gitlab`, or `bitbucket` |
| `external_repository_id` | FK |
| `number` | PR/MR number |
| `title`, `body`, `url` | |
| `state` | `open` or `closed` |
| `author_login` | |
| `source_branch`, `target_branch` | |
| `source_sha`, `target_sha`, `merge_commit_sha` | |
| `merged` | boolean |
| `merged_at`, `opened_at`, `closed_at`, `last_event_at` | |
| Unique index | `[provider, external_repository_id, number]` |

**`external_builds`** — CI builds

| Column | Notes |
|---|---|
| `provider`, `external_repository_id` | |
| `provider_build_id` | Provider's build/run ID |
| `build_number` | Run number / pipeline IID |
| `name` | Display name |
| `status` | `queued`, `in_progress`, `success`, `failed`, `canceled`, `skipped`, `unknown` |
| `conclusion` | Provider-specific result |
| `sha`, `ref`, `branch_name`, `author_login` | |
| `started_at`, `finished_at`, `last_event_at` | |
| Unique index | `[provider, external_repository_id, provider_build_id]` |

**`external_deployments`** — Deployments

| Column | Notes |
|---|---|
| `provider`, `external_repository_id` | |
| `provider_deployment_id` | |
| `environment_name` | |
| `environment_url` | |
| `status` | `pending`, `in_progress`, `success`, `failed`, `canceled`, `rolled_back`, `unknown` |
| `sha`, `ref`, `branch_name` | |
| `creator_login` | |
| `started_at`, `completed_at`, `last_event_at` | |
| Unique index | `[provider, external_repository_id, provider_deployment_id, environment_name]` |

**`external_provider_events`** — Webhook event journal

| Column | Notes |
|---|---|
| `provider`, `delivery_id`, `event_type` | |
| `payload` | Raw JSON |
| `status` | `pending`, `processed`, `failed`, `ignored` |
| `processed_at` | |
| `error_message` | |
| Unique index | `[provider, delivery_id, event_type]` |

**`external_automation_events`** — Automation dedup

| Column | Notes |
|---|---|
| `issue_id` | FK |
| `external_provider_event_id` | Optional FK to triggering event |
| `marker` | Unique compound key for deduplication |
| `action_type` | |
| Unique index | `[issue_id, marker]` |

### Junction Tables

All follow the same pattern: `id`, `{entity}_id`, `issue_id`, unique index on `[{entity}_id, issue_id]`.

| Table | Links |
|---|---|
| `external_branch_issues` | Branches ↔ Issues |
| `external_commit_issues` | Commits ↔ Issues |
| `external_pull_request_issues` | PRs ↔ Issues |
| `external_build_issues` | Builds ↔ Issues |
| `external_deployment_issues` | Deployments ↔ Issues |

### Settings Tables

**`development_integration_project_settings`** — Per-project config
**`development_integration_automation_rules`** — Custom rules
**`development_integration_environment_rules`** — Per-env deployment rules
**`external_provider_user_mappings`** — Provider user → Redmine user

---

## Permissions

| Permission | What it allows |
|---|---|
| `view_development_integration` | See the Development tab on issues; view project settings tabs |
| `manage_development_integration` | Edit project dev settings; add/edit/deactivate repositories |
| `manage_provider_webhooks` | Register webhooks; retry failed provider events |
| `trigger_provider_sync` | Trigger manual reconciliation |

All permissions can be assigned per project via Roles & Permissions.

---

## Architecture

### Design Principles

1. **Layered, not replacing**: This plugin layers provider intelligence on top of Redmine's native SCM. It does NOT replace Redmine SCM — it tracks external development activity alongside it
2. **Provider-neutral models**: Single `ExternalPullRequest` model serves both GitHub PRs and GitLab MRs
3. **Soft-delete everywhere**: Branches, repositories preserve historical data on deactivation
4. **Zero custom CSS**: All views use native Redmine classes (`changeset journal`, `table.list`, `box tabular`, `splitcontent`, etc.)
5. **Async by default**: All webhook processing is async via ActiveJob; only signature verification is synchronous
6. **Strong deduplication**: Two-layer idempotency — delivery ID at the event level, marker key at the automation level

### File Layout

```
lib/redmine_dev_integration/
├── provider_clients/        # GitHub, GitLab, Bitbucket API clients
│   ├── base_client.rb       # Paginated HTTP, JSON helpers, Link header parsing
│   ├── github_client.rb
│   ├── gitlab_client.rb
│   └── bitbucket_client.rb
├── oauth/                   # OAuth2 authorization services
│   ├── github_authorization_service.rb
│   ├── gitlab_authorization_service.rb
│   ├── bitbucket_authorization_service.rb
│   └── token_store.rb       # Encrypted token storage
├── github_*_processor.rb    # GitHub webhook event processors (push, PR, workflow, deployment)
├── gitlab_*_processor.rb    # GitLab webhook event processors (push, MR, pipeline, deployment)
├── bitbucket_*_processor.rb # Bitbucket webhook event processors (push, PR, pipeline, deployment)
├── external_provider_event_processor.rb  # Event dispatcher
├── automation_service.rb    # Automation engine (legacy mappings + custom rules)
├── smart_commit_service.rb  # Smart commit execution
├── smart_commit_parser.rb   # Smart commit syntax parsing
├── reconciliation_service.rb # API reconciliation
├── scheduled_reconciliation_runner.rb # Batch reconciliation runner
├── webhook_registration_service.rb # Provider webhook CRUD
├── issue_linker.rb          # Issue key → Issue resolution bridge
├── issue_key_extractor.rb   # Regex-based key extraction
└── ...
```

### Monkey Patches

All patches use `prepend` (safe, chainable) or `include` (for model associations):

| Patch | What it adds |
|---|---|
| `ProjectPatch` | `has_many :external_repositories`, `has_one :development_integration_project_setting` |
| `SettingPatch` | Preserves secrets on empty form submissions; encrypts OAuth tokens |
| `IssuesControllerPatch` | Serves Development tab content via AJAX |
| `IssuesHelperPatch` | Adds "Development" tab to issue history tabs |
| `ProjectsHelperPatch` | Adds 4 dev integration tabs to project settings |
| `ChangesetPatch` | After-save hook for `ChangesetIssueKeyLinker` |

---

## Troubleshooting

### Webhooks not being received

1. Check provider is enabled: Administration → Plugins → Configure → Accept {provider} webhooks
2. Verify the webhook URL is accessible from the internet
3. Check Redmine logs for signature/token verification errors
4. Check the **Provider Events** tab in project settings — events should appear as "processed" or "failed"

### Events showing as "ignored"

The event payload didn't match any provider processor. Check:
- The event type is supported (see webhook table above)
- The repository is mapped in the project (provider + provider_repository_id must match)
- The repository is active

### Repository not found in webhook

1. Verify `provider_repository_id` in the repository settings matches the actual provider ID
   - GitHub: numeric ID from repository settings or API
   - GitLab: numeric project ID
   - Bitbucket: UUID from repository settings
2. Ensure the repository is active (not deactivated)

### Webhook registration fails

Common causes:
- Missing `admin:repo_hook` scope (classic GitHub PAT) or Webhooks write permission (fine-grained PAT)
- Repository admin permission missing on the connected account
- Token expired or revoked
- Self-hosted GitLab base URL not configured

For raw API errors, the plugin transforms them into human-readable messages with possible causes listed.

### OAuth connection fails

- **"Invalid OAuth state"**: Session expired. Click Connect again
- **"Token exchange failed"**: Verify client ID/secret and callback URL exactly match your OAuth App settings
- **"401 Unauthorized" during repo lookup**: Check the OAuth token has correct scopes (`repo` + `admin:repo_hook` for GitHub, `api` for GitLab)
- **Empty client ID/secret**: Both fields must be filled. Submitting an empty password field preserves the existing value

### Smart commits not working

1. Ensure `redmine_issue_keys` plugin is installed
2. Enable "Smart commits" in project Development Settings
3. Commit messages must contain the exact issue key (e.g., `PROJ-123`) followed by a command
4. Commands are space-separated: `PROJ-123 #done #time 2h`
5. The push webhook must be received for smart commits to be processed

### Reconciliation returns "skipped"

| Reason | Meaning |
|---|---|
| `unsupported_provider` | Provider is not `github`, `gitlab`, or `bitbucket` |
| `credentials_missing` | No API token configured in global settings |
| `inactive_repository` | Repository has `active: false` |
| `project_mismatch` | Repository belongs to a different project |
| `api_failure` | Provider API returned an error |

---

## Known Limitations

1. **No commit-level linking from pushes**: Push processors scan branch names AND individual commit messages for issue keys. Both work. However, individual commit messages in pushes that don't match the issue key pattern are not linked to issues
2. **No Bitbucket OAuth repo listing**: Repository auto-populate via "Load repositories" works for GitHub and GitLab via OAuth. Bitbucket uses the `list_repositories` API method but the feature is not wired to the UI
3. **`#done`/`#in-progress`/`#resolve` all map to same status**: Smart commit transitions don't distinguish "in progress" from "done". All three commands use the "PR merged" status mapping
4. **Reconciliation limits**: Max 500 items per type (PRs, builds, deployments) per reconciliation run. If you have more items since the last sync, additional runs are needed
5. **No organization-wide repo browser**: Repository addition requires knowing the provider repository ID. OAuth repo listing helps populate the fields but doesn't provide a full browser
6. **No commit-level display on issues**: The development panel shows `ExternalCommit` records from webhooks (with SHA, message, author, branch) and native SCM `Changeset` records. Individual external commits are not shown if the push webhook wasn't received
7. **Auto-reconciliation runs in-process**: The request-triggered auto-reconciliation runs synchronously on the first request after 15 minutes. On high-traffic instances, this could add latency. Use cron-based rake tasks for production

---

## Running Tests

```sh
# Full plugin test suite (unit + functional + integration)
bin/rails test plugins/redmine_dev_integration/test/

# System tests only (require Chrome/ChromeDriver)
bin/rails test:system

# With code coverage
COVERAGE=1 bin/rails test plugins/redmine_dev_integration/test/

# Plugin rake task (does NOT run system tests)
bundle exec rake redmine:plugins:test NAME=redmine_dev_integration RAILS_ENV=test
```

**Test database setup:**
```sh
RAILS_ENV=test bin/rails db:create
RAILS_ENV=test bin/rails db:migrate
bundle exec rake redmine:plugins:migrate NAME=redmine_dev_integration RAILS_ENV=test
bundle exec rake redmine:plugins:migrate NAME=redmine_issue_keys RAILS_ENV=test
```

---

## Integration with redmine_issue_keys

Both plugins are designed to work together:

```
redmine_issue_keys                redmine_dev_integration
├── Issue.find_by_issue_key()     ├── IssueKeyExtractor (regex)
├── issue_key column              ├── IssueLinker (bridge)
├── display_id (key or #id)       ├── Webhook processors (scan text)
├── Commit scanning               ├── Smart commits (parse + execute)
└── API responses                 └── Dev panel (display data)
```

**Flow:**
1. `redmine_issue_keys` adds issue keys (`PROJ-123`) and `Issue.find_by_issue_key(key)`
2. `redmine_dev_integration`'s `IssueKeyExtractor` finds key patterns in webhook data
3. `IssueLinker` resolves keys via the companion plugin's `find_by_issue_key`
4. Branches, commits, PRs, builds, and deployments are linked via junction tables
5. The Development tab on issues displays all linked records

**Without `redmine_issue_keys`**: All records are still created and stored. Issue linking does not occur. No errors raised — the linker gracefully returns empty results.
