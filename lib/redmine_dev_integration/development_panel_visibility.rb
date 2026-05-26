# frozen_string_literal: true

module RedmineDevIntegration
  module DevelopmentPanelVisibility
    module_function

    def visible_for_project?(project)
      return true unless defined?(DevelopmentIntegrationProjectSetting)

      setting = project_setting_for(project)
      return true if setting.nil?

      value = if setting.respond_to?(:show_dev_panel)
        setting.show_dev_panel
      else
        setting.try(:[], :show_dev_panel)
      end

      value != false
    end

    def project_setting_for(project)
      if project.respond_to?(:development_integration_project_setting)
        project.development_integration_project_setting
      elsif project.respond_to?(:development_integration_project_settings)
        project.development_integration_project_settings
      end
    end
  end
end
