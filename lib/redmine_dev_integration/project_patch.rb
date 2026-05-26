# frozen_string_literal: true

module RedmineDevIntegration
  module ProjectPatch
    def self.included(base)
      base.class_eval do
        has_many :external_repositories, class_name: 'ExternalRepository', foreign_key: :redmine_project_id, dependent: :delete_all
        has_one :development_integration_project_setting, class_name: 'DevelopmentIntegrationProjectSetting', dependent: :destroy
      end
    end
  end
end
