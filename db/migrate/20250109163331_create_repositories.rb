class CreateRepositories < ActiveRecord::Migration[7.1]
  def change
    create_table :repositories do |t|
      t.string :github_id, null: false, index: { unique: true }
      t.string :full_name, null: false, index: true
      t.text :description
      t.jsonb :raw_data, null: false
      t.timestamp :fetched_at, null: false

      t.timestamps
    end

    # Index on JSONB for efficient querying
    add_index :repositories, :raw_data, using: :gin
  end
end
