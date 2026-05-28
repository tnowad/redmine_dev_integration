# frozen_string_literal: true

class CreateExternalReviews < ActiveRecord::Migration[6.1]
  def up
    return if table_exists?(:external_reviews)

    create_table :external_reviews do |t|
      t.references :external_pull_request, null: false, foreign_key: true
      t.string :provider, null: false
      t.string :provider_review_id
      t.string :reviewer_login
      t.string :reviewer_name
      t.string :state, null: false  # APPROVED, CHANGES_REQUESTED, COMMENTED, DISMISSED
      t.text :body
      t.datetime :submitted_at
      t.timestamps
    end

    add_index :external_reviews, [:provider, :external_pull_request_id, :provider_review_id],
              unique: true, name: 'idx_external_reviews_unique'
  end

  def down
    drop_table :external_reviews if table_exists?(:external_reviews)
  end
end
