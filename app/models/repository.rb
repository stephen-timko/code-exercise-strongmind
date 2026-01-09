class Repository < ApplicationRecord
  # Associations
  has_many :push_events, foreign_key: 'enriched_repository_id', dependent: :nullify

  # Validations
  validates :github_id, presence: true, uniqueness: true
  validates :full_name, presence: true
  validates :raw_data, presence: true
  validates :fetched_at, presence: true

  # Scopes
  scope :by_github_id, ->(id) { where(github_id: id) }
  scope :by_full_name, ->(name) { where(full_name: name) }

  # Instance methods
  def cache_fresh?(ttl: 24.hours)
    return false if fetched_at.nil?
    fetched_at > (Time.current - ttl)
  end

  def cache_stale?(ttl: 24.hours)
    !cache_fresh?(ttl: ttl)
  end
end
