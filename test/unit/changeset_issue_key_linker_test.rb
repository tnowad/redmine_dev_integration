# frozen_string_literal: true

require_relative '../test_helper'

class ChangesetIssueKeyLinkerTest < ActiveSupport::TestCase
  def setup
    @linker = RedmineDevIntegration::IssueLinker
    @service = RedmineDevIntegration::ChangesetIssueKeyLinker.new
  end

  def test_creates_issue_link_from_issue_key_in_commit_message
    issue = Issue.new
    issue.stubs(:id).returns(42)
    issue.stubs(:project).returns(Project.new.tap { |p| p.stubs(:id).returns(1) })

    linker_result = @linker::Result.new(
      matched_keys: ['RAK-1'],
      issue_ids: [42]
    )

    @linker.any_instance.stubs(:link).returns(linker_result)
    Issue.stubs(:where).with(id: [42]).returns([issue])
    Setting.stubs(:commit_cross_project_ref?).returns(true)

    issues_collection = mock('issues_collection')
    issues_collection.stubs(:include?).with(issue).returns(false)
    issues_collection.expects(:<<).with(issue)

    project = Project.new
    project.stubs(:id).returns(1)

    changeset = mock('changeset')
    changeset.stubs(:comments).returns('follow RAK-1')
    changeset.stubs(:project).returns(project)
    changeset.stubs(:issues).returns(issues_collection)

    @service.call(changeset: changeset)
  end

  def test_preserves_numeric_refs_alongside_issue_keys
    issue = Issue.new
    issue.stubs(:id).returns(10)
    issue.stubs(:project).returns(Project.new.tap { |p| p.stubs(:id).returns(1) })

    linker_result = @linker::Result.new(
      matched_keys: ['RAK-1'],
      issue_ids: [10]
    )

    @linker.any_instance.stubs(:link).returns(linker_result)
    Issue.stubs(:where).with(id: [10]).returns([issue])
    Setting.stubs(:commit_cross_project_ref?).returns(true)

    issues_collection = mock('issues_collection')
    issues_collection.stubs(:include?).with(issue).returns(false)
    issues_collection.expects(:<<).with(issue)

    project = Project.new
    project.stubs(:id).returns(1)

    changeset = mock('changeset')
    changeset.stubs(:comments).returns('Refs RAK-1 and #123')
    changeset.stubs(:project).returns(project)
    changeset.stubs(:issues).returns(issues_collection)

    @service.call(changeset: changeset)
  end

  def test_resolves_lowercase_issue_key
    issue = Issue.new
    issue.stubs(:id).returns(7)
    issue.stubs(:project).returns(Project.new.tap { |p| p.stubs(:id).returns(1) })

    linker_result = @linker::Result.new(
      matched_keys: ['RAK-1'],
      issue_ids: [7]
    )

    @linker.any_instance.stubs(:link).with('rak-1').returns(linker_result)
    Issue.stubs(:where).with(id: [7]).returns([issue])
    Setting.stubs(:commit_cross_project_ref?).returns(true)

    issues_collection = mock('issues_collection')
    issues_collection.stubs(:include?).with(issue).returns(false)
    issues_collection.expects(:<<).with(issue)

    project = Project.new
    project.stubs(:id).returns(1)

    changeset = mock('changeset')
    changeset.stubs(:comments).returns('rak-1')
    changeset.stubs(:project).returns(project)
    changeset.stubs(:issues).returns(issues_collection)

    @service.call(changeset: changeset)
  end

  def test_links_multiple_issue_keys_in_one_commit
    issue_rak = Issue.new
    issue_rak.stubs(:id).returns(5)
    issue_rak.stubs(:project).returns(Project.new.tap { |p| p.stubs(:id).returns(1) })

    issue_bug = Issue.new
    issue_bug.stubs(:id).returns(6)
    issue_bug.stubs(:project).returns(Project.new.tap { |p| p.stubs(:id).returns(1) })

    linker_result = @linker::Result.new(
      matched_keys: %w[RAK-1 BUG-2],
      issue_ids: [5, 6]
    )

    @linker.any_instance.stubs(:link).returns(linker_result)
    Issue.stubs(:where).with(id: [5, 6]).returns([issue_rak, issue_bug])
    Setting.stubs(:commit_cross_project_ref?).returns(true)

    issues_collection = mock('issues_collection')
    issues_collection.stubs(:include?).with(issue_rak).returns(false)
    issues_collection.expects(:<<).with(issue_rak)
    issues_collection.stubs(:include?).with(issue_bug).returns(false)
    issues_collection.expects(:<<).with(issue_bug)

    project = Project.new
    project.stubs(:id).returns(1)

    changeset = mock('changeset')
    changeset.stubs(:comments).returns('RAK-1 and BUG-2')
    changeset.stubs(:project).returns(project)
    changeset.stubs(:issues).returns(issues_collection)

    @service.call(changeset: changeset)
  end

  def test_does_not_fail_on_unknown_issue_key
    linker_result = @linker::Result.new(
      matched_keys: ['UNKNOWN-999'],
      issue_ids: []
    )

    @linker.any_instance.stubs(:link).returns(linker_result)
    Issue.stubs(:where).with(id: []).returns([])

    project = Project.new
    project.stubs(:id).returns(1)

    changeset = mock('changeset')
    changeset.stubs(:comments).returns('UNKNOWN-999')
    changeset.stubs(:project).returns(project)

    assert_nothing_raised { @service.call(changeset: changeset) }
  end

  def test_respects_cross_project_ref_disabled
    issue = Issue.new
    issue.stubs(:id).returns(42)

    changeset_project = Project.new
    changeset_project.stubs(:id).returns(1)

    other_project = Project.new
    other_project.stubs(:id).returns(2)
    changeset_project.stubs(:==).with(other_project).returns(false)
    changeset_project.stubs(:is_ancestor_of?).with(other_project).returns(false)
    changeset_project.stubs(:is_descendant_of?).with(other_project).returns(false)

    issue.stubs(:project).returns(other_project)

    linker_result = @linker::Result.new(
      matched_keys: ['RAK-1'],
      issue_ids: [42]
    )

    @linker.any_instance.stubs(:link).returns(linker_result)
    Issue.stubs(:where).with(id: [42]).returns([issue])
    Setting.stubs(:commit_cross_project_ref?).returns(false)

    changeset = mock('changeset')
    changeset.stubs(:comments).returns('RAK-1')
    changeset.stubs(:project).returns(changeset_project)
    changeset.stubs(:issues).returns([])

    assert_nothing_raised { @service.call(changeset: changeset) }
  end

  def test_excludes_already_linked_issues
    issue = Issue.new
    issue.stubs(:id).returns(42)
    issue.stubs(:project).returns(Project.new.tap { |p| p.stubs(:id).returns(1) })

    linker_result = @linker::Result.new(
      matched_keys: ['RAK-1'],
      issue_ids: [42]
    )

    @linker.any_instance.stubs(:link).returns(linker_result)
    Issue.stubs(:where).with(id: [42]).returns([issue])
    Setting.stubs(:commit_cross_project_ref?).returns(true)

    issues_collection = mock('issues_collection')
    issues_collection.stubs(:include?).with(issue).returns(true)
    issues_collection.expects(:<<).never

    project = Project.new
    project.stubs(:id).returns(1)

    changeset = mock('changeset')
    changeset.stubs(:comments).returns('RAK-1 again')
    changeset.stubs(:project).returns(project)
    changeset.stubs(:issues).returns(issues_collection)

    @service.call(changeset: changeset)
  end

  def test_returns_early_on_blank_comments
    changeset = mock('changeset')
    changeset.stubs(:comments).returns('')

    @linker.any_instance.expects(:link).never

    @service.call(changeset: changeset)
  end
end
