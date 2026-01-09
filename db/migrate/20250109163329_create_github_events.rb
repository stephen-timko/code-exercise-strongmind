class CreateGitHubEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :github_events do |t|
      t.string :event_id, null: false, index: { unique: true }
      t.string :event_type, null: false, index: true
      t.jsonb :raw_payload, null: false
      t.timestamp :ingested_at, null: false
      t.timestamp :processed_at

      t.timestamps
    end

    # Index on JSONB for efficient querying
    add_index :github_events, :raw_payload, using: :gin
  end
end
