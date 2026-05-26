# frozen_string_literal: true

module RedmineDevIntegration
  module ProjectsHelperPatch
    def project_settings_tabs
      tabs = super

      if User.current.allowed_to?(:view_development_integration, @project)
        tabs << {
          name: 'dev_integration_settings',
          action: :view_development_integration,
          partial: 'projects/settings/dev_integration_settings',
          label: :label_dev_integration_settings
        }
        tabs << {
          name: 'dev_integration_repos',
          action: :view_development_integration,
          partial: 'projects/settings/dev_integration_repos',
          label: :label_dev_integration_repos
        }
        tabs << {
          name: 'dev_integration_events',
          action: :view_development_integration,
          partial: 'projects/settings/dev_integration_events',
          label: :label_dev_integration_events
        }
        tabs << {
          name: 'dev_integration_users',
          action: :view_development_integration,
          partial: 'projects/settings/dev_integration_user_mappings',
          label: :label_dev_integration_users
        }
      end

      tabs
    end
  end
end
