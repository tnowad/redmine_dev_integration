# frozen_string_literal: true

module RedmineDevIntegration
  module IssuesControllerPatch
    def issue_tab
      return super unless params[:name] == 'development'
      return render_error(status: 422) unless request.xhr?
      return render_forbidden unless User.current.allowed_to?(:view_development_integration, @project)
      return render_403 unless DevelopmentPanelVisibility.visible_for_project?(@project)

      @development_panel_data =
        if defined?(RedmineDevIntegration::IssueDevelopmentPanelData)
          RedmineDevIntegration::IssueDevelopmentPanelData.new(@issue)
        end

      render partial: 'issues/tabs/development'
    end
  end
end
