# frozen_string_literal: true

require_relative '../../test_helper'

class Projects::DoraMetricsControllerTest < Redmine::ControllerTest
  fixtures :projects, :users, :roles, :members, :member_roles, :repositories

  def setup
    @request.session[:user_id] = 2
    @project = Project.find(1)
    @project.enable_module!(:redmine_dev_integration)

    @repo = ExternalRepository.create!(
      provider: 'github',
      provider_repository_id: 'dora-ctlr-test-999',
      owner: 'redmine',
      repo_name: 'redmine',
      full_name: 'redmine/redmine',
      url: 'https://github.com/redmine/redmine',
      redmine_project: @project,
      active: true
    )
  end

  def test_show_requires_permission
    @request.session[:user_id] = 3
    get :show, params: { project_id: @project.identifier }
    assert_response :forbidden
  end

  def test_show_returns_success_with_permission
    Role.find(1).add_permission! :view_development_integration
    get :show, params: { project_id: @project.identifier }
    assert_response :success
  end

  def test_show_renders_dora_metrics_page
    Role.find(1).add_permission! :view_development_integration
    get :show, params: { project_id: @project.identifier }
    assert_response :success
    assert_select 'h2', text: /DORA Metrics/i
  end

  def test_show_defaults_to_30_day_range
    Role.find(1).add_permission! :view_development_integration
    get :show, params: { project_id: @project.identifier }
    assert_response :success
    assert_select '.icon-checked', text: /Last 30 days/i
  end

  def test_show_with_7_day_range
    Role.find(1).add_permission! :view_development_integration
    get :show, params: { project_id: @project.identifier, range: 7 }
    assert_response :success
    assert_select '.icon-checked', text: /Last 7 days/i
  end

  def test_show_with_90_day_range
    Role.find(1).add_permission! :view_development_integration
    get :show, params: { project_id: @project.identifier, range: 90 }
    assert_response :success
    assert_select '.icon-checked', text: /Last 90 days/i
  end

  def test_show_with_invalid_range_defaults_to_30
    Role.find(1).add_permission! :view_development_integration
    get :show, params: { project_id: @project.identifier, range: 15 }
    assert_response :success
    assert_select '.icon-checked', text: /Last 30 days/i
  end

  def test_show_with_deployment_data_renders_metric_cards
    Role.find(1).add_permission! :view_development_integration
    now = Time.current
    ExternalDeployment.create!(
      provider: 'github',
      external_repository: @repo,
      provider_deployment_id: 'ctlr-deploy-1',
      environment_name: 'production',
      status: 'success',
      completed_at: now - 1.day
    )

    get :show, params: { project_id: @project.identifier }
    assert_response :success
    assert_select '.total-hours'
    assert_select '.box'
    assert_select '#deploy-trend-chart'
  end

  def test_show_no_data_message_when_no_deployments
    Role.find(1).add_permission! :view_development_integration
    get :show, params: { project_id: @project.identifier }
    assert_response :success
    assert_select 'p.nodata'
  end

  def test_show_includes_chart_js_tag
    Role.find(1).add_permission! :view_development_integration
    get :show, params: { project_id: @project.identifier }
    assert_response :success
    assert_select 'script[src*="chart.min"]'
  end
end
