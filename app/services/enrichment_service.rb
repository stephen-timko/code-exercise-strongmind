class EnrichmentService
  class EnrichmentError < StandardError; end

  # Default cache TTL (24 hours)
  DEFAULT_CACHE_TTL = 24.hours

  # Enrich a PushEvent with actor and repository data
  # @param push_event [PushEvent] The PushEvent to enrich
  # @param cache_ttl [ActiveSupport::Duration] Cache TTL for checking freshness
  # @return [Hash] Result with :actor_enriched, :repository_enriched, :status
  def self.enrich(push_event, cache_ttl: DEFAULT_CACHE_TTL)
    new(push_event, cache_ttl: cache_ttl).enrich
  end

  def initialize(push_event, cache_ttl: DEFAULT_CACHE_TTL)
    @push_event = push_event
    @cache_ttl = cache_ttl
    @client = GitHubApiClient.new
    @event_payload = push_event.github_event.raw_payload
  end

  def enrich
    @push_event.mark_enrichment_in_progress!

    actor_enriched = enrich_actor
    repository_enriched = enrich_repository

    # Update enrichment status based on results
    if actor_enriched && repository_enriched
      @push_event.mark_enrichment_completed!
      status = :completed
    elsif actor_enriched || repository_enriched
      # Partial enrichment - still mark as completed (some data is better than none)
      @push_event.mark_enrichment_completed!
      status = :partial
    else
      @push_event.mark_enrichment_failed!
      status = :failed
    end

    {
      actor_enriched: actor_enriched,
      repository_enriched: repository_enriched,
      status: status
    }
  rescue StandardError => e
    Rails.logger.error("Enrichment failed for PushEvent #{@push_event.id}: #{e.message}")
    @push_event.mark_enrichment_failed!
    raise EnrichmentError, "Failed to enrich PushEvent: #{e.message}"
  end

  private

  def enrich_actor
    actor_url = extract_actor_url
    return false unless actor_url

    # Extract actor ID from payload (will be set from API response if not available)
    actor_id_from_payload = extract_actor_id(actor_url)

    # Check if actor is already cached and fresh (if we have ID)
    if actor_id_from_payload.present?
      actor = Actor.find_by(github_id: actor_id_from_payload)
      if actor&.cache_fresh?(ttl: @cache_ttl)
        Rails.logger.debug("Actor #{actor_id_from_payload} cache is fresh, skipping fetch")
        @push_event.update!(actor: actor)
        return true
      end
    end

    # Fetch actor data from GitHub
    response = @client.fetch_resource(actor_url)
    return false if response[:not_modified] || response[:data].nil?

    actor_data = response[:data]
    return false unless actor_data['id'].present?

    # Use ID from API response (most reliable)
    actor_id = actor_data['id'].to_s
    
    # Create or update actor record
    actor = Actor.find_or_initialize_by(github_id: actor_id)
    actor.assign_attributes(
      login: actor_data['login'] || actor_data['name'] || '',
      avatar_url: actor_data['avatar_url'],
      raw_data: actor_data,
      fetched_at: Time.current
    )

    if actor.save
      @push_event.update!(actor: actor)
      Rails.logger.info("Enriched actor #{actor_id} for PushEvent #{@push_event.id}")
      true
    else
      Rails.logger.error("Failed to save actor #{actor_id}: #{actor.errors.full_messages.join(', ')}")
      false
    end
  rescue GitHubApiClient::ApiError, GitHubApiClient::NetworkError => e
    Rails.logger.error("Failed to fetch actor data: #{e.message}")
    false
  rescue StandardError => e
    Rails.logger.error("Error enriching actor: #{e.message}")
    false
  end

  def enrich_repository
    repository_url = extract_repository_url
    return false unless repository_url

    # Extract repository ID from payload (will be set from API response if not available)
    repository_id_from_payload = extract_repository_id(repository_url)

    # Check if repository is already cached and fresh (if we have ID)
    if repository_id_from_payload.present?
      repository = Repository.find_by(github_id: repository_id_from_payload)
      if repository&.cache_fresh?(ttl: @cache_ttl)
        Rails.logger.debug("Repository #{repository_id_from_payload} cache is fresh, skipping fetch")
        @push_event.update!(enriched_repository: repository)
        return true
      end
    end

    # Fetch repository data from GitHub
    response = @client.fetch_resource(repository_url)
    return false if response[:not_modified] || response[:data].nil?

    repo_data = response[:data]
    return false unless repo_data['id'].present?

    # Use ID from API response (most reliable)
    repository_id = repo_data['id'].to_s
    
    # Create or update repository record
    repository = Repository.find_or_initialize_by(github_id: repository_id)
    repository.assign_attributes(
      full_name: repo_data['full_name'] || repo_data['name'] || @push_event.repository_id,
      description: repo_data['description'],
      raw_data: repo_data,
      fetched_at: Time.current
    )

    if repository.save
      @push_event.update!(enriched_repository: repository)
      Rails.logger.info("Enriched repository #{repository_id} for PushEvent #{@push_event.id}")
      true
    else
      Rails.logger.error("Failed to save repository #{repository_id}: #{repository.errors.full_messages.join(', ')}")
      false
    end
  rescue GitHubApiClient::ApiError, GitHubApiClient::NetworkError => e
    Rails.logger.error("Failed to fetch repository data: #{e.message}")
    false
  rescue StandardError => e
    Rails.logger.error("Error enriching repository: #{e.message}")
    false
  end

  def extract_actor_url
    # Try actor.url first (most reliable)
    url = @event_payload.dig('actor', 'url')
    return url if url.present?

    # Fallback: construct URL from actor.login
    login = @event_payload.dig('actor', 'login')
    return "https://api.github.com/users/#{login}" if login.present?

    # Fallback: try actor.html_url and convert to API URL
    html_url = @event_payload.dig('actor', 'html_url')
    if html_url.present?
      # Convert https://github.com/username to https://api.github.com/users/username
      html_url.gsub('github.com', 'api.github.com/users')
    end
  end

  def extract_actor_id(actor_url)
    # Use numeric ID from payload (most reliable)
    actor_id = @event_payload.dig('actor', 'id')
    return actor_id.to_s if actor_id.present?

    # If ID not available, we'll fetch and use the ID from the response
    # For now, return nil and let the fetch handle it
    nil
  end

  def extract_repository_url
    # Try repo.url first (most reliable)
    url = @event_payload.dig('repo', 'url')
    return url if url.present?

    # Fallback: construct URL from repo.full_name or repo.name
    full_name = @event_payload.dig('repo', 'full_name') || @event_payload.dig('repo', 'name')
    return "https://api.github.com/repos/#{full_name}" if full_name.present?

    # Fallback: use repository_id from PushEvent
    return "https://api.github.com/repos/#{@push_event.repository_id}" if @push_event.repository_id.present?

    nil
  end

  def extract_repository_id(repository_url)
    # Use numeric ID from payload (most reliable)
    repo_id = @event_payload.dig('repo', 'id')
    return repo_id.to_s if repo_id.present?

    # If ID not available, we'll fetch and use the ID from the response
    # For now, return nil and let the fetch handle it
    nil
  end
end
