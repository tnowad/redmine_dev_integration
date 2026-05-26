# frozen_string_literal: true

module RedmineDevIntegration
  class IssueDevelopmentPanelData
    ScmBranchRef = Struct.new(:name, :repository, :state, :updated_at, keyword_init: true)

    attr_reader :issue

    def initialize(issue)
      @issue = issue
    end

    def branches
      ExternalBranch
        .includes(:external_repository)
        .joins(:external_repository, :external_branch_issues)
        .where(external_branch_issues: {issue_id: issue.id})
        .where(external_branches: {state: 'active'})
        .where(external_repositories: {redmine_project_id: issue.project_id})
        .order('external_repositories.full_name ASC, external_branches.name ASC')
    end

    def scm_branches
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

    def builds
      ExternalBuild
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
      issue
        .changesets
        .visible
        .preload(:repository, :user)
    end

    def external_commits
      ExternalCommit
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
      ExternalDeployment
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
      ExternalPullRequest
        .includes(:external_repository)
        .joins(:external_repository, :external_pull_request_issues)
        .where(external_pull_request_issues: {issue_id: issue.id})
        .where(external_repositories: {redmine_project_id: issue.project_id})
        .order('external_repositories.full_name ASC, external_pull_requests.number ASC')
    end

    private

    def issue_key_pattern
      @issue_key_pattern ||= /\b#{Regexp.escape(issue.issue_key)}\b/i
    end
  end
end
