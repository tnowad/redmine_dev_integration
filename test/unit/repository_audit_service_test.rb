# frozen_string_literal: true

require_relative '../test_helper'

class RepositoryAuditServiceTest < ActiveSupport::TestCase
  fixtures :projects, :repositories, :users

  def setup
    @service = RedmineDevIntegration::RepositoryAuditService.new
    @project = projects(:projects_001)
    @actor = users(:users_002)
    @logged_lines = []
    logged_lines = @logged_lines
    @fake_logger = Object.new
    @fake_logger.define_singleton_method(:method_missing) do |method, *args|
      logged_lines << [method, args]
      nil
    end
    @fake_logger.define_singleton_method(:respond_to_missing?) do |_method, _include_private|
      true
    end

    Rails.stubs(:logger).returns(@fake_logger)
    @repository = ExternalRepository.create!(
      provider: 'github',
      provider_repository_id: '123',
      owner: 'redmine',
      repo_name: 'redmine_dev_integration',
      full_name: 'redmine/redmine_dev_integration',
      url: 'https://github.com/redmine/redmine_dev_integration',
      redmine_project: @project,
      redmine_repository: repositories(:repositories_001),
      active: true
    )
    User.current = @actor
    @logged_lines.clear
  end

  def teardown
    User.current = nil
  end

  def test_connected_audit_logs_structured_line_and_returns_result
    assert_audit_logged(:connected, 'Repository connected')
  end

  def test_updated_audit_logs_structured_line_and_returns_result
    assert_audit_logged(:updated, 'Repository updated')
  end

  def test_deactivated_audit_logs_structured_line_and_returns_result
    assert_audit_logged(:deactivated, 'Repository deactivated')
  end

  def test_scm_linked_audit_logs_structured_line_and_returns_result
    assert_audit_logged(:scm_linked, 'SCM repository linked')
  end

  def test_scm_unlinked_audit_logs_structured_line_and_returns_result
    assert_audit_logged(:scm_unlinked, 'SCM repository unlinked')
  end

  def test_repository_audit_does_not_create_issue_journals
    assert_no_difference "Journal.where(journalized_type: 'Issue').count" do
      result = @service.call(
        action: :connected,
        repository: @repository,
        project: @project,
        actor: @actor
      )

      assert_predicate result, :logged?
    end

    assert_audit_line_logged(/action=connected/)
  end

  private

  def assert_audit_logged(action, message)
    result = nil

    assert_no_difference "Journal.where(journalized_type: 'Issue').count" do
      result = @service.call(
        action: action,
        repository: @repository,
        project: @project,
        actor: @actor
      )
    end

    assert_predicate result, :logged?
    assert_equal action.to_s, result.payload[:action]
    assert_equal message, result.payload[:message]
    assert_equal 'github', result.payload[:provider]
    assert_equal 'redmine/redmine_dev_integration', result.payload[:full_name]
    assert_equal @project.identifier, result.payload[:project_identifier]
    assert_equal @actor.login, result.payload[:actor_login]
    assert_equal @repository.redmine_repository_id, result.payload[:redmine_repository_id]

    assert_audit_line_logged(
      /redmine_dev_integration\.repository_audit .*action=#{action} .*message="#{Regexp.escape(message)}" .*provider=github .*full_name="redmine\/redmine_dev_integration" .*project="ecookbook" .*actor="jsmith"/
    )
  end

  def assert_audit_line_logged(pattern)
    audit_lines = @logged_lines.select { |level, _args| level == :info }.map { |_, args| args.first }.grep(/redmine_dev_integration\.repository_audit/)

    assert_equal 1, audit_lines.length
    assert_match(pattern, audit_lines.first)
  end
end
