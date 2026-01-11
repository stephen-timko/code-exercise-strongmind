namespace :github do
  desc "Ingest GitHub events from the public events API"
  task ingest: :environment do
    # Ensure services are loaded before jobs to avoid constant resolution issues during eager loading
    # Reference service classes to trigger Zeitwerk autoloading in the correct order
    # This ensures exception classes are defined before jobs try to reference them
    GitHubApiClient
    EnrichmentService
    PushEventParser
    
    # Ensure all application code is loaded
    Rails.application.eager_load! unless Rails.application.config.eager_load
    
    puts "Starting GitHub events ingestion..."
    
    begin
      # Retrieve last ETag to avoid unnecessary polling
      last_etag = JobState.get('github_events_etag')
      
      # Run ingestion job synchronously for rake task
      etag = IngestGitHubEventsJob.new.perform(etag: last_etag)
      
      # Store ETag for next run
      JobState.set('github_events_etag', etag) if etag
      
      puts "Ingestion completed successfully"
    rescue StandardError => e
      puts "Ingestion failed: #{e.message}"
      puts e.backtrace.join("\n") if Rails.env.development?
      exit 1
    end
  end

  desc "Enrich pending PushEvents with actor and repository data"
  task enrich: :environment do
    puts "Starting enrichment of pending PushEvents..."
    
    batch_size = ENV.fetch('BATCH_SIZE', '10').to_i
    pending_events = PushEvent.pending_enrichment.limit(batch_size)
    
    if pending_events.empty?
      puts "No pending PushEvents to enrich"
      exit 0
    end
    
    puts "Processing #{pending_events.count} pending PushEvents..."
    
    enriched_count = 0
    failed_count = 0
    
    pending_events.each do |push_event|
      begin
        result = EnrichmentService.enrich(push_event)
        if result[:status] == :completed || result[:status] == :partial
          enriched_count += 1
          puts "  ✓ Enriched PushEvent #{push_event.id}"
        else
          failed_count += 1
          puts "  ✗ Failed to enrich PushEvent #{push_event.id}"
        end
      rescue StandardError => e
        failed_count += 1
        puts "  ✗ Error enriching PushEvent #{push_event.id}: #{e.message}"
      end
    end
    
    puts "\nEnrichment completed: #{enriched_count} succeeded, #{failed_count} failed"
  end

  desc "Show ingestion statistics"
  task stats: :environment do
    puts "\n=== GitHub Events Ingestion Statistics ===\n"
    
    total_events = GitHubEvent.count
    push_events = GitHubEvent.push_events.count
    processed_events = GitHubEvent.processed.count
    unprocessed_events = GitHubEvent.unprocessed.count
    
    puts "Total Events: #{total_events}"
    puts "Push Events: #{push_events}"
    puts "Processed Events: #{processed_events}"
    puts "Unprocessed Events: #{unprocessed_events}"
    
    total_push_events = PushEvent.count
    enriched_push_events = PushEvent.enriched.count
    pending_enrichment = PushEvent.pending_enrichment.count
    failed_enrichment = PushEvent.failed_enrichment.count
    
    puts "\n--- Push Events ---"
    puts "Total Push Events: #{total_push_events}"
    puts "Enriched: #{enriched_push_events}"
    puts "Pending Enrichment: #{pending_enrichment}"
    puts "Failed Enrichment: #{failed_enrichment}"
    
    actors_count = Actor.count
    repositories_count = Repository.count
    
    puts "\n--- Enrichment Data ---"
    puts "Actors: #{actors_count}"
    puts "Repositories: #{repositories_count}"
    
    if total_push_events > 0
      enrichment_rate = (enriched_push_events.to_f / total_push_events * 100).round(2)
      puts "\nEnrichment Rate: #{enrichment_rate}%"
    end
    
    puts "\n==========================================\n"
  end
end
