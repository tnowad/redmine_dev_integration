# frozen_string_literal: true

module RedmineDevIntegration
  class DevIntegrationHookListener < Redmine::Hook::ViewListener
    def view_issues_sidebar_issues_bottom(context = {})
      @issue = context[:issue] || context[:controller]&.instance_variable_get(:@issue)
      return '' unless @issue

      controller = context[:controller]
      controller.send(:render_to_string, {
        partial: 'issues/sidebar/dev_integration_summary',
        locals: { issue: @issue }
      })
    end
  end
end
