# frozen_string_literal: true

module Projects
  class ReleasesController < ApplicationController
    before_action :find_project
    before_action :authorize_development_integration

    def index
      repo_ids = @project.external_repositories.active.pluck(:id)
      @releases = ExternalRelease.published
        .where(external_repository_id: repo_ids)
        .includes(:external_repository, :issues, :external_deployments)
        .order(released_at: :desc)
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
