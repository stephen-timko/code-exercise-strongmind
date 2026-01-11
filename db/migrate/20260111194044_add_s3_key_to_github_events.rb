class AddS3KeyToGitHubEvents < ActiveRecord::Migration[7.1]
  def change
    add_column :github_events, :s3_key, :string, null: true
    add_index :github_events, :s3_key
    # Make raw_payload nullable when S3 is used
    change_column_null :github_events, :raw_payload, true
  end
end
