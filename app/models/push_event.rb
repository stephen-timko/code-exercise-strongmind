class PushEvent < ApplicationRecord
  # Enrichment status constants
  ENRICHMENT_STATUS_PENDING = 'pending'
  ENRICHMENT_STATUS_IN_PROGRESS = 'in_progress'
  ENRICHMENT_STATUS_COMPLETED = 'completed'
  ENRICHMENT_STATUS_FAILED = 'failed'

  ENRICHMENT_STATUSES = [
    ENRICHMENT_STATUS_PENDING,
    ENRICHMENT_STATUS_IN_PROGRESS,
    ENRICHMENT_STATUS_COMPLETED,
    ENRICHMENT_STATUS_FAILED
  ].freeze

  # Associations
  belongs_to :github_event
  belongs_to :actor, optional: true
  belongs_to :enriched_repository, class_name: 'Repository', optional: true

  # Validations
  validates :repository_id, presence: true
  validates :push_id, presence: true, uniqueness: true
  validates :ref, presence: true
  validates :head, presence: true
  # before can be empty string for initial commits, but must not be nil
  validates :before, exclusion: { in: [nil] }
  validates :enrichment_status, inclusion: { in: ENRICHMENT_STATUSES }

  # Scopes
  scope :by_repository, ->(repo_id) { where(repository_id: repo_id) }
  scope :by_enrichment_status, ->(status) { where(enrichment_status: status) }
  scope :enriched, -> { where(enrichment_status: ENRICHMENT_STATUS_COMPLETED) }
  scope :pending_enrichment, -> { where(enrichment_status: ENRICHMENT_STATUS_PENDING) }
  scope :failed_enrichment, -> { where(enrichment_status: ENRICHMENT_STATUS_FAILED) }

  # Instance methods
  def enriched?
    enrichment_status == ENRICHMENT_STATUS_COMPLETED
  end

  def pending_enrichment?
    enrichment_status == ENRICHMENT_STATUS_PENDING
  end

  def mark_enrichment_in_progress!
    update!(enrichment_status: ENRICHMENT_STATUS_IN_PROGRESS)
  end

  def mark_enrichment_completed!
    update!(enrichment_status: ENRICHMENT_STATUS_COMPLETED)
  end

  def mark_enrichment_failed!
    update!(enrichment_status: ENRICHMENT_STATUS_FAILED)
  end
end
