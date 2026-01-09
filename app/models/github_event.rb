class GitHubEvent < ApplicationRecord
  # Validations
  validates :event_id, presence: true, uniqueness: true
  validates :event_type, presence: true
  validates :raw_payload, presence: true
  validates :ingested_at, presence: true

  # Associations
  has_one :push_event, dependent: :destroy

  # Scopes
  scope :by_type, ->(type) { where(event_type: type) }
  scope :push_events, -> { where(event_type: 'PushEvent') }
  scope :processed, -> { where.not(processed_at: nil) }
  scope :unprocessed, -> { where(processed_at: nil) }

  # Instance methods
  def push_event?
    event_type == 'PushEvent'
  end

  def processed?
    processed_at.present?
  end

  def mark_as_processed!
    update!(processed_at: Time.current)
  end
end
