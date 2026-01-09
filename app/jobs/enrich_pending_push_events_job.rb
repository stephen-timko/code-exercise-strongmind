class EnrichPendingPushEventsJob < ApplicationJob
  queue_as :default

  # Process batch of pending PushEvents
  # @param batch_size [Integer] Number of PushEvents to process (default: 10)
  def perform(batch_size: 10)
    pending_events = PushEvent.pending_enrichment.limit(batch_size)

    if pending_events.empty?
      Rails.logger.info("No pending PushEvents to enrich")
      return
    end

    Rails.logger.info("Processing #{pending_events.count} pending PushEvents for enrichment")

    enriched_count = 0
    failed_count = 0

    pending_events.each do |push_event|
      begin
        # Enqueue individual enrichment job
        EnrichPushEventJob.perform_later(push_event.id)
        enriched_count += 1
      rescue StandardError => e
        Rails.logger.error("Failed to enqueue enrichment for PushEvent #{push_event.id}: #{e.message}")
        failed_count += 1
      end
    end

    Rails.logger.info("Enqueued #{enriched_count} PushEvents for enrichment, #{failed_count} failed")
  end
end
