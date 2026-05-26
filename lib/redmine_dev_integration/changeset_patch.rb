# frozen_string_literal: true

module RedmineDevIntegration
  module ChangesetPatch
    def self.included(base)
      base.class_eval do
        after_create :link_issue_keys_from_commit_message
      end
    end

    private

    def link_issue_keys_from_commit_message
      RedmineDevIntegration::ChangesetIssueKeyLinker.call(changeset: self)
    end
  end
end
