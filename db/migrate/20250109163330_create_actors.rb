class CreateActors < ActiveRecord::Migration[7.1]
  def change
    create_table :actors do |t|
      t.string :github_id, null: false, index: { unique: true }
      t.string :login, null: false, index: true
      t.string :avatar_url
      t.jsonb :raw_data, null: false
      t.timestamp :fetched_at, null: false

      t.timestamps
    end

    # Index on JSONB for efficient querying
    add_index :actors, :raw_data, using: :gin
  end
end
