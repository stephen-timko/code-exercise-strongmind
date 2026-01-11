class GitHubEvent < ApplicationRecord
  # Validations
  validates :event_id, presence: true, uniqueness: true
  validates :event_type, presence: true
  validates :ingested_at, presence: true
  validate :raw_payload_or_s3_key_present

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

  # Override raw_payload reader to retrieve from S3 if stored there
  def raw_payload
    if s3_key.present?
      # Retrieve from S3 (with caching for performance)
      @raw_payload_from_s3 ||= ObjectStorageService.retrieve(s3_key)
    else
      # Return from JSONB column
      read_attribute(:raw_payload)
    end
  rescue ObjectStorageService::StorageError, ObjectStorageService::NotFoundError => e
    Rails.logger.error("Failed to retrieve payload from S3 for key #{s3_key}: #{e.message}")
    # Fallback to JSONB if S3 retrieval fails
    read_attribute(:raw_payload)
  end

  # Store payload (in S3 if enabled, otherwise in JSONB)
  # @param payload [Hash] The payload to store
  def store_payload(payload)
    # Try to store in S3 if enabled
    s3_key_result = ObjectStorageService.store(event_id, payload)
    
    if s3_key_result.present?
      # Stored in S3 - set s3_key and leave raw_payload as nil
      self.s3_key = s3_key_result
      self.raw_payload = nil
    else
      # S3 disabled or failed - store in JSONB
      self.s3_key = nil
      self.raw_payload = payload
    end
  end

  private

  def raw_payload_or_s3_key_present
    # Check database columns directly (not the method override)
    if read_attribute(:raw_payload).blank? && s3_key.blank?
      errors.add(:base, 'Either raw_payload or s3_key must be present')
    end
  end
end
