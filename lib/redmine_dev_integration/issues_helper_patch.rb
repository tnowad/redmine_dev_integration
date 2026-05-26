# frozen_string_literal: true

module RedmineDevIntegration
  module IssuesHelperPatch
    def issue_history_tabs
      tabs = super

      if User.current.allowed_to?(:view_development_integration, @project) &&
         DevelopmentPanelVisibility.visible_for_project?(@project)
        tabs << {
          name: 'development',
          label: :label_development_tab,
          remote: true,
          onclick: "getRemoteTab('development', '#{tab_issue_path(@issue, name: 'development')}', '#{issue_path(@issue, tab: 'development')}')"
        }
      end

      tabs
    end
  end
end
