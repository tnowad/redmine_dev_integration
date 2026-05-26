# frozen_string_literal: true

module RedmineDevIntegration
  class AuditNoteService
    Result = Struct.new(:status, :journal, :marker, keyword_init: true) do
      def created?
        status == :created
      end

      def skipped?
        status == :skipped
      end
    end

    MARKER_PREFIX = '[redmine-dev-integration:'.freeze

    def call(issue:, note:, marker:, provider_url: nil, external_object_id: nil, user: User.current)
      return skipped_result(:blank_note) if note.blank?
      return skipped_result(:blank_marker) if marker.blank?
      return skipped_result(:duplicate) if duplicate_marker?(issue, marker)

      journal = Journal.new(
        journalized: issue,
        user: user,
        notes: build_notes(note, marker, provider_url, external_object_id)
      )

      if journal.save
        Result.new(status: :created, journal: journal, marker: marker.to_s)
      else
        skipped_result(:save_failed)
      end
    end

    private

    def build_notes(note, marker, provider_url, external_object_id)
      parts = [marker_token(marker)]
      parts << "provider_url=#{provider_url}" if provider_url.present?
      parts << "external_object_id=#{external_object_id}" if external_object_id.present?
      ([parts.join(' ')] + [note.to_s]).join("\n")
    end

    def marker_token(marker)
      "#{MARKER_PREFIX}#{marker}]"
    end

    def duplicate_marker?(issue, marker)
      token = marker_token(marker)
      pattern = "%#{ActiveRecord::Base.sanitize_sql_like(token)}%"
      issue.journals.where("notes LIKE ?", pattern).exists?
    end

    def skipped_result(reason)
      Result.new(status: :skipped, journal: nil, marker: reason.to_s)
    end
  end
end
