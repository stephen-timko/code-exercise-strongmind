class PushEventParser
  class ParseError < StandardError; end

  # Parse a raw GitHub event payload and extract PushEvent fields
  # @param event_payload [Hash] Raw GitHub event JSON payload
  # @return [Hash] Structured data with keys: repository_id, push_id, ref, head, before
  # @raise [ParseError] if event is not a PushEvent or required fields are missing
  def self.parse(event_payload)
    new(event_payload).parse
  end

  def initialize(event_payload)
    @payload = event_payload.is_a?(Hash) ? event_payload : {}
  end

  def parse
    validate_push_event!
    
    result = {
      repository_id: extract_repository_id,
      push_id: extract_push_id,
      ref: extract_ref,
      head: extract_head,
      before: extract_before
    }
    
    validate_required_fields!(result)
    result
  rescue StandardError => e
    raise ParseError, "Failed to parse PushEvent: #{e.message}"
  end

  private

  def validate_push_event!
    unless @payload['type'] == 'PushEvent'
      raise ParseError, "Event type is not PushEvent: #{@payload['type']}"
    end
  end

  def extract_repository_id
    # Try full_name first (e.g., "owner/repo"), then fall back to id
    repo = @payload.dig('repo')
    return nil unless repo

    full_name = repo['full_name'] || repo['name']
    return full_name if full_name

    # Fallback to repository ID as string if full_name not available
    repo_id = repo['id']
    repo_id.to_s if repo_id
  end

  def extract_push_id
    push_id = @payload.dig('payload', 'push_id')
    return push_id.to_s if push_id

    # Fallback: use event id as push_id if push_id is missing
    # Event id is unique per event, ensuring uniqueness
    event_id = @payload['id']
    return event_id.to_s if event_id

    nil
  end

  def extract_ref
    ref = @payload.dig('payload', 'ref')
    return ref if ref

    # Try alternative location
    @payload.dig('ref') || ''
  end

  def extract_head
    head = @payload.dig('payload', 'head')
    return head if head

    # Try to get from commits array if available
    commits = @payload.dig('payload', 'commits')
    return commits.last['sha'] if commits.is_a?(Array) && commits.any?

    # Fallback: try head_commit
    @payload.dig('payload', 'head_commit', 'id') || 
    @payload.dig('payload', 'head_commit', 'sha') || 
    ''
  end

  def extract_before
    before = @payload.dig('payload', 'before')
    return before if before

    # Fallback: empty string if not available
    ''
  end

  def validate_required_fields!(result)
    missing_fields = []
    missing_fields << 'repository_id' if result[:repository_id].blank?
    missing_fields << 'push_id' if result[:push_id].blank?
    missing_fields << 'ref' if result[:ref].blank?
    missing_fields << 'head' if result[:head].blank?
    # before can be empty string for initial commits, but not nil
    missing_fields << 'before' if result[:before].nil?

    if missing_fields.any?
      raise ParseError, "Missing required fields: #{missing_fields.join(', ')}"
    end
  end
end
