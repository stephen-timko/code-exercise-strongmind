class CreateJobStates < ActiveRecord::Migration[7.1]
  def change
    create_table :job_states do |t|
      t.string :key, null: false, index: { unique: true }
      t.text :value

      t.timestamps
    end
  end
end
