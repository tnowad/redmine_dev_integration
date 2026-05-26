# frozen_string_literal: true

require_relative '../../../../test/application_system_test_case'
require_relative '../support/dev_integration_test_factory'

class DevelopmentTabTest < ApplicationSystemTestCase
  include DevIntegrationTestFactory

  def setup
    @project = Project.generate!(identifier: 'dev-tab-test', name: 'Dev Tab Test', issue_key_prefix: 'DEV')
    @project.enable_module!(:redmine_dev_integration)

    Role.find(1).add_permission!(:view_development_integration)
    Role.find(1).add_permission!(:manage_development_integration)

    @issue = create_issue_with_key(project: @project)
    @repo = create_external_repository(project: @project, provider: 'github', full_name: 'owner/dev-repo', provider_repository_id: '54321')
    @dev_data = create_dev_panel_data(issue: @issue, repository: @repo)

    ExternalCommit.create!(
      provider: 'github',
      external_repository: @repo,
      provider_commit_id: 'commit-abc123',
      sha: 'abc123def456789',
      short_sha: 'abc123d',
      message: "Fix #{@issue.issue_key} login issue",
      author_login: 'dev1',
      url: "https://github.com/#{@repo.full_name}/commit/abc123def456789",
      branch_name: "feature/#{@issue.issue_key}-login",
      committed_at: 2.days.ago,
      last_event_at: 2.days.ago
    )
    ext_commit = ExternalCommit.last
    ExternalCommitIssue.create!(external_commit: ext_commit, issue: @issue)
  end

  test "user sees development tab on issue page" do
    log_user('admin', 'admin')
    visit issue_path(@issue)

    assert_selector '.tabs ul li a', text: 'Development'
  end

  test "user clicks development tab and content loads via ajax" do
    log_user('admin', 'admin')
    visit issue_path(@issue)

    click_link 'Development'

    wait_for_ajax

    within '#tab-content-development' do
      assert_selector 'h3', text: 'Revisions'
      assert_selector "[id^='external-commit-']"
    end
  end

  test "development tab shows branches section" do
    log_user('admin', 'admin')
    visit issue_path(@issue)

    click_link 'Development'
    wait_for_ajax

    within '#tab-content-development' do
      assert_selector 'h3', text: 'Branch'
      assert_selector "div#branch-#{@dev_data[:branch].id}"
    end
  end

  test "development tab shows builds section" do
    log_user('admin', 'admin')
    visit issue_path(@issue)

    click_link 'Development'
    wait_for_ajax

    within '#tab-content-development' do
      assert_selector 'h3', text: 'Builds'
      assert_selector "div#build-#{@dev_data[:build].id}"
      assert_text @dev_data[:build].name
      assert_selector ".badge-status-#{@dev_data[:build].status}"
    end
  end

  test "development tab shows deployments section" do
    log_user('admin', 'admin')
    visit issue_path(@issue)

    click_link 'Development'
    wait_for_ajax

    within '#tab-content-development' do
      assert_selector 'h3', text: 'Deployments'
      assert_selector "div#deployment-#{@dev_data[:deployment].id}"
      assert_text @dev_data[:deployment].environment_name
      assert_selector ".badge-status-#{@dev_data[:deployment].status}"
    end
  end

  test "development tab shows pull requests section" do
    log_user('admin', 'admin')
    visit issue_path(@issue)

    click_link 'Development'
    wait_for_ajax

    within '#tab-content-development' do
      assert_selector 'h3', text: 'Pull requests'
      assert_selector "div#pr-#{@dev_data[:pull_request].id}"
      assert_text "##{@dev_data[:pull_request].number}"
      assert_text @dev_data[:pull_request].title
      assert_text @dev_data[:pull_request].state
    end
  end

  test "external commits use changeset journal pattern" do
    log_user('admin', 'admin')
    visit issue_path(@issue)

    click_link 'Development'
    wait_for_ajax

    within '#tab-content-development' do
      assert_selector 'div.changeset.journal'
    end
  end

  test "provider link icons exist with target blank" do
    log_user('admin', 'admin')
    visit issue_path(@issue)

    click_link 'Development'
    wait_for_ajax

    within '#tab-content-development' do
      assert_selector "a.icon-only.icon-link[target='_blank']"
    end
  end

  test "user without view_development_integration permission does not see the tab" do
    role = Role.generate!(name: 'View Only', permissions: [])
    user = User.generate!(login: 'viewonly', firstname: 'View', lastname: 'Only', password: 'viewOnly123')
    Member.create!(project: @project, user: user, roles: [role])
    @project.enable_module!(:redmine_dev_integration)

    log_user('viewonly', 'viewOnly123')
    visit issue_path(@issue)

    assert_no_selector '.tabs ul li a', text: 'Development'
  end

  test "builds section hidden when show_builds is false" do
    setting = DevelopmentIntegrationProjectSetting.for_project(@project)
    setting.update!(show_builds: false)

    log_user('admin', 'admin')
    visit issue_path(@issue)

    click_link 'Development'
    wait_for_ajax

    within '#tab-content-development' do
      assert_no_selector 'h3', text: 'Builds'
    end
  end

  test "deployments section hidden when show_deployments is false" do
    setting = DevelopmentIntegrationProjectSetting.for_project(@project)
    setting.update!(show_deployments: false)

    log_user('admin', 'admin')
    visit issue_path(@issue)

    click_link 'Development'
    wait_for_ajax

    within '#tab-content-development' do
      assert_no_selector 'h3', text: 'Deployments'
    end
  end

  test "empty state shows nodata when issue has no dev data" do
    empty_issue = create_issue_with_key(project: @project, subject: 'No dev data issue')

    log_user('admin', 'admin')
    visit issue_path(empty_issue)

    click_link 'Development'
    wait_for_ajax

    assert_selector '#tab-content-development p.nodata', visible: :all
  end
end
