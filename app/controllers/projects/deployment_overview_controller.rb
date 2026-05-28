# frozen_string_literal: true

module Projects
  class DeploymentOverviewController < ApplicationController
    before_action :find_project
    before_action :authorize_development_integration

    def index
      @deployments_by_env = RedmineDevIntegration::DeploymentOverviewService.new.call(project: @project)
    end

    private

    def find_project
      @project = Project.find(params[:project_id])
    rescue ActiveRecord::RecordNotFound
      render_404
    end

    def authorize_development_integration
      render_403 unless User.current.allowed_to?(:view_development_integration, @project)
    end
  end
end
