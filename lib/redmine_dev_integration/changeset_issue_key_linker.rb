# frozen_string_literal: true

module RedmineDevIntegration
  class ChangesetIssueKeyLinker
    def self.call(changeset:)
      new.call(changeset: changeset)
    end

    def call(changeset:)
      comments = changeset.comments
      return if comments.blank?

      linker = IssueLinker.new
      result = linker.link(comments)
      return if result.issue_ids.empty?

      issues = Issue.where(id: result.issue_ids).to_a

      unless Setting.commit_cross_project_ref?
        project = changeset.project
        issues.select! do |issue|
          issue.project &&
            (project == issue.project ||
             project.is_ancestor_of?(issue.project) ||
             project.is_descendant_of?(issue.project))
        end
      end

      issues.each do |issue|
        changeset.issues << issue unless changeset.issues.include?(issue)
      end

      return unless changeset.respond_to?(:revision) && changeset.revision.present?

      SmartCommitService.call(
        project: changeset.project,
        commit_sha: changeset.revision.to_s,
        commit_message: comments,
        user: changeset.user
      )
    end
  end
end
