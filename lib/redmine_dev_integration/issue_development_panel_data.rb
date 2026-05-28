# frozen_string_literal: true

module RedmineDevIntegration
  class IssueDevelopmentPanelData
    ScmBranchRef = Struct.new(:name, :repository, :state, :updated_at, keyword_init: true)

    attr_reader :issue

    def initialize(issue)
      @issue = issue
    end

    def branches
      @branches ||= ExternalBranch
        .includes(:external_repository)
        .joins(:external_repository, :external_branch_issues)
        .where(external_branch_issues: {issue_id: issue.id})
        .where(external_branches: {state: 'active'})
        .where(external_repositories: {redmine_project_id: issue.project_id})
        .order('external_repositories.full_name ASC, external_branches.name ASC')
    end

    def scm_branches
      @scm_branches ||= begin
        return [] if issue.issue_key.to_s.blank?

        issue.project.repositories.flat_map do |repository|
          next [] unless repository.respond_to?(:branches)

          Array(repository.branches).filter_map do |branch_name|
            branch = branch_name.to_s
            next if branch.blank?
            next unless branch.match?(issue_key_pattern)

            ScmBranchRef.new(
              name: branch,
              repository: repository,
              state: 'active',
              updated_at: nil
            )
          end
        rescue StandardError
          []
        end.sort_by(&:name)
      end
    end

    def builds
      @builds ||= ExternalBuild
        .includes(:external_repository)
        .joins(:external_repository, :external_build_issues)
        .where(external_build_issues: {issue_id: issue.id})
        .where(external_repositories: {redmine_project_id: issue.project_id})
        .order(
          Arel.sql('COALESCE(external_builds.last_event_at, external_builds.updated_at) DESC'),
          Arel.sql('external_builds.updated_at DESC')
        )
    end

    def commits
      @commits ||= issue
        .changesets
        .visible
        .preload(:repository, :user)
    end

    def external_commits
      @external_commits ||= ExternalCommit
        .includes(:external_repository)
        .joins(:external_repository, :external_commit_issues)
        .where(external_commit_issues: {issue_id: issue.id})
        .where(external_repositories: {redmine_project_id: issue.project_id})
        .order(
          Arel.sql('COALESCE(external_commits.committed_at, external_commits.created_at) DESC'),
          Arel.sql('external_commits.created_at DESC')
        )
    end

    def deployments
      @deployments ||= ExternalDeployment
        .includes(:external_repository)
        .joins(:external_repository, :external_deployment_issues)
        .where(external_deployment_issues: {issue_id: issue.id})
        .where(external_repositories: {redmine_project_id: issue.project_id})
        .order(
          Arel.sql('COALESCE(external_deployments.last_event_at, external_deployments.updated_at) DESC'),
          Arel.sql('external_deployments.updated_at DESC')
        )
    end

    def pull_requests
      @pull_requests ||= ExternalPullRequest
        .includes(:external_repository)
        .joins(:external_repository, :external_pull_request_issues)
        .where(external_pull_request_issues: {issue_id: issue.id})
        .where(external_repositories: {redmine_project_id: issue.project_id})
        .order('external_repositories.full_name ASC, external_pull_requests.number ASC')
    end

    def releases
      @releases ||= ExternalRelease
        .includes(:external_repository)
        .joins(:external_repository, :external_release_issues)
        .where(external_release_issues: {issue_id: issue.id})
        .where(external_repositories: {redmine_project_id: issue.project_id})
        .order(
          Arel.sql('COALESCE(external_releases.released_at, external_releases.updated_at) DESC'),
          Arel.sql('external_releases.updated_at DESC')
        )
    end

    def incidents
      @incidents ||= ExternalIncident
        .includes(:external_repository)
        .joins(:external_repository, :external_incident_issues)
        .where(external_incident_issues: {issue_id: issue.id})
        .where(external_repositories: {redmine_project_id: issue.project_id})
        .order(created_at: :desc)
    end

    def branch_count
      @branch_count ||= ExternalBranch.joins(:external_repository, :external_branch_issues)
        .where(external_branch_issues: { issue_id: issue.id })
        .where(external_branches: { state: 'active' })
        .where(external_repositories: { redmine_project_id: issue.project_id })
        .count
    end

    def pull_request_count
      @pull_request_count ||= ExternalPullRequest.joins(:external_repository, :external_pull_request_issues)
        .where(external_pull_request_issues: { issue_id: issue.id })
        .where(external_repositories: { redmine_project_id: issue.project_id })
        .count
    end

    def build_count
      @build_count ||= ExternalBuild.joins(:external_repository, :external_build_issues)
        .where(external_build_issues: { issue_id: issue.id })
        .where(external_repositories: { redmine_project_id: issue.project_id })
        .count
    end

    def deployment_count
      @deployment_count ||= ExternalDeployment.joins(:external_repository, :external_deployment_issues)
        .where(external_deployment_issues: { issue_id: issue.id })
        .where(external_repositories: { redmine_project_id: issue.project_id })
        .count
    end

    def commit_count
      @commit_count ||= ExternalCommit.joins(:external_repository, :external_commit_issues)
        .where(external_commit_issues: { issue_id: issue.id })
        .where(external_repositories: { redmine_project_id: issue.project_id })
        .count
    end

    def any_dev_data?
      @any_dev_data ||= begin
        return false unless issue.project_id
        repo_ids = ExternalRepository.where(redmine_project_id: issue.project_id, active: true).pluck(:id)
        return false if repo_ids.empty?

        ExternalBranchIssue
          .joins(:external_branch)
          .where(external_branch_issues: { issue_id: issue.id })
          .where(external_branches: { external_repository_id: repo_ids, state: 'active' })
          .exists? ||
        ExternalPullRequestIssue
          .joins(:external_pull_request)
          .where(external_pull_request_issues: { issue_id: issue.id })
          .where(external_pull_requests: { external_repository_id: repo_ids })
          .exists? ||
        ExternalBuildIssue
          .joins(:external_build)
          .where(external_build_issues: { issue_id: issue.id })
          .where(external_builds: { external_repository_id: repo_ids })
          .exists? ||
        ExternalDeploymentIssue
          .joins(:external_deployment)
          .where(external_deployment_issues: { issue_id: issue.id })
          .where(external_deployments: { external_repository_id: repo_ids })
          .exists? ||
        ExternalCommitIssue
          .joins(:external_commit)
          .where(external_commit_issues: { issue_id: issue.id })
          .where(external_commits: { external_repository_id: repo_ids })
          .exists?
      end
    end

    private

    def issue_key_pattern
      @issue_key_pattern ||= /\b#{Regexp.escape(issue.issue_key)}\b/i
    end
  end
end
