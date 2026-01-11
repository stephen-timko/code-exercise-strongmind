class JobState < ApplicationRecord
  validates :key, presence: true, uniqueness: true

  # Get a job state value by key
  def self.get(key)
    find_by(key: key)&.value
  end

  # Set a job state value by key
  def self.set(key, value)
    state = find_or_initialize_by(key: key)
    state.value = value
    state.save!
    value
  end
end
