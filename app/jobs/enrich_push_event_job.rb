class EnrichPushEventJob < ApplicationJob
  queue_as :default

  # Retry on rate limit errors after delay
  retry_on GitHubApiClient::RateLimitExceeded, wait: :polynomially_longer, attempts: 3
  # Retry on network errors
  retry_on GitHubApiClient::NetworkError, wait: :polynomially_longer, attempts: 5
  # Retry on enrichment errors (transient failures)
  retry_on EnrichmentService::EnrichmentError, wait: :polynomially_longer, attempts: 3
  # Don't retry on record not found (PushEvent was deleted)
  discard_on ActiveRecord::RecordNotFound

  # Process a single PushEvent by ID
  # @param push_event_id [Integer] The ID of the PushEvent to enrich
  def perform(push_event_id)
    push_event = PushEvent.find(push_event_id)

    # Skip if already enriched or in progress
    if push_event.enriched?
      Rails.logger.debug("PushEvent #{push_event_id} already enriched, skipping")
      return
    end

    if push_event.enrichment_status == PushEvent::ENRICHMENT_STATUS_IN_PROGRESS
      Rails.logger.debug("PushEvent #{push_event_id} enrichment in progress, skipping")
      return
    end

    Rails.logger.info("Enriching PushEvent #{push_event_id} (push_id: #{push_event.push_id})")

    result = EnrichmentService.enrich(push_event)

    case result[:status]
    when :completed
      Rails.logger.info("Successfully enriched PushEvent #{push_event_id} (actor: #{result[:actor_enriched]}, repository: #{result[:repository_enriched]})")
    when :partial
      Rails.logger.warn("Partially enriched PushEvent #{push_event_id} (actor: #{result[:actor_enriched]}, repository: #{result[:repository_enriched]})")
    when :failed
      Rails.logger.error("Failed to enrich PushEvent #{push_event_id}")
      raise EnrichmentService::EnrichmentError, "Enrichment failed for PushEvent #{push_event_id}"
    end
  end
end
