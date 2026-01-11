class IngestGitHubEventsJob < ApplicationJob
  queue_as :default

  # Retry on rate limit errors after delay
  retry_on GitHubApiClient::RateLimitExceeded, wait: :polynomially_longer, attempts: 3
  # Retry on network errors
  retry_on GitHubApiClient::NetworkError, wait: :polynomially_longer, attempts: 5
  # Don't retry on API errors (400, 404, etc.)
  discard_on GitHubApiClient::ApiError

  def perform(etag: nil)
    client = GitHubApiClient.new
    response = client.fetch_events(etag: etag)

    # Handle 304 Not Modified
    if response[:not_modified]
      Rails.logger.info("GitHub events not modified (304), skipping ingestion")
      return
    end

    events = response[:data] || []
    rate_limit_info = response[:rate_limit_info] || {}

    Rails.logger.info("Ingesting #{events.size} events from GitHub API. Rate limit: #{rate_limit_info[:remaining]}/#{rate_limit_info[:limit]}")

    ingested_count = 0
    push_events_created = 0
    push_events_errors = 0

    events.each do |event_data|
      begin
        github_event = store_raw_event(event_data)
        next unless github_event

        ingested_count += 1

        # Only process PushEvent type
        if github_event.push_event?
          push_event = create_push_event(github_event, event_data)
          push_events_created += 1 if push_event
          push_events_errors += 1 unless push_event
        end
      rescue StandardError => e
        Rails.logger.error("Error processing event #{event_data['id']}: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n")) if Rails.env.development?
        push_events_errors += 1
      end
    end

    Rails.logger.info("Ingestion complete: #{ingested_count} events ingested, #{push_events_created} PushEvents created, #{push_events_errors} errors")
    Rails.logger.info("Rate limit remaining: #{rate_limit_info[:remaining]}/#{rate_limit_info[:limit]}")

    # Return ETag for next request
    response[:etag]
  end

  private

  def store_raw_event(event_data)
    return nil unless event_data.is_a?(Hash)
    return nil unless event_data['id'].present?

    # Idempotent: use find_or_initialize_by to prevent duplicates
    github_event = GitHubEvent.find_or_initialize_by(event_id: event_data['id'].to_s)

    # Skip if already exists and processed
    if github_event.persisted? && github_event.processed?
      Rails.logger.debug("Event #{event_data['id']} already processed, skipping")
      return github_event
    end

    github_event.assign_attributes(
      event_type: event_data['type'] || 'Unknown',
      ingested_at: Time.current
    )
    
    # Store payload (in S3 if enabled, otherwise in JSONB)
    github_event.store_payload(event_data)

    if github_event.save
      github_event
    else
      Rails.logger.error("Failed to save event #{event_data['id']}: #{github_event.errors.full_messages.join(', ')}")
      nil
    end
  rescue ActiveRecord::RecordNotUnique
    # Race condition: another process already created this event
    Rails.logger.debug("Event #{event_data['id']} already exists (race condition), fetching existing")
    GitHubEvent.find_by(event_id: event_data['id'].to_s)
  rescue StandardError => e
    Rails.logger.error("Error storing raw event #{event_data['id']}: #{e.message}")
    nil
  end

  def create_push_event(github_event, event_data)
    return nil if github_event.push_event.present?

    # Parse the event to extract structured data
    parsed_data = PushEventParser.parse(event_data)

    # Idempotent: use find_or_initialize_by to prevent duplicates
    push_event = PushEvent.find_or_initialize_by(push_id: parsed_data[:push_id])

    if push_event.persisted?
      Rails.logger.debug("PushEvent #{parsed_data[:push_id]} already exists, skipping")
      return push_event
    end

    push_event.assign_attributes(
      github_event: github_event,
      repository_id: parsed_data[:repository_id],
      ref: parsed_data[:ref],
      head: parsed_data[:head],
      before: parsed_data[:before],
      enrichment_status: PushEvent::ENRICHMENT_STATUS_PENDING
    )

    if push_event.save
      github_event.mark_as_processed!
      push_event
    else
      Rails.logger.error("Failed to save PushEvent #{parsed_data[:push_id]}: #{push_event.errors.full_messages.join(', ')}")
      nil
    end
  rescue PushEventParser::ParseError => e
    Rails.logger.error("Failed to parse PushEvent from event #{event_data['id']}: #{e.message}")
    nil
  rescue ActiveRecord::RecordNotUnique
    # Race condition: another process already created this push event
    Rails.logger.debug("PushEvent #{parsed_data[:push_id]} already exists (race condition), fetching existing")
    PushEvent.find_by(push_id: parsed_data[:push_id])
  rescue StandardError => e
    Rails.logger.error("Error creating PushEvent: #{e.message}")
    nil
  end
end
