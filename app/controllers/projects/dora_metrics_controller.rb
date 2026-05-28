# frozen_string_literal: true

module Projects
  class DoraMetricsController < ApplicationController
    menu_item :dora_metrics
    before_action :find_project
    before_action :authorize_development_integration

    helper_method :dora_band_class

    def show
      range_days = params[:range].to_i
      range_days = 30 unless [7, 30, 90].include?(range_days)
      @range = range_days.days
      @range_days = range_days
      @metrics = RedmineDevIntegration::MetricsService.new.call(project: @project, range: @range)
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

    def dora_band_class(band)
      case band
      when 'elite' then 'closed'
      when 'high' then 'open'
      when 'medium' then 'locked'
      else 'locked'
      end
    end
  end
end
