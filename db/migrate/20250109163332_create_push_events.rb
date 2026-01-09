class CreatePushEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :push_events do |t|
      t.references :github_event, null: false, foreign_key: true, index: true
      t.string :repository_id, null: false, index: true
      t.string :push_id, null: false, index: { unique: true }
      t.string :ref, null: false
      t.string :head, null: false
      t.string :before, null: false
      t.references :actor, null: true, foreign_key: true, index: true
      t.references :enriched_repository, null: true, foreign_key: { to_table: :repositories }, index: true
      t.string :enrichment_status, default: 'pending', index: true

      t.timestamps
    end

    # Composite index for common query patterns
    add_index :push_events, [:repository_id, :created_at]
  end
end
