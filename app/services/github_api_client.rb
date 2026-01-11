class GitHubApiClient
  BASE_URL = 'https://api.github.com'.freeze
  EVENTS_ENDPOINT = '/events'.freeze

  # Rate limit constants (unauthenticated)
  RATE_LIMIT_REQUESTS = 60
  RATE_LIMIT_WINDOW = 1.hour

  class RateLimitExceeded < StandardError; end
  class ApiError < StandardError; end
  class NetworkError < StandardError; end
  class NotModifiedError < StandardError
    attr_reader :response
    def initialize(message, response = nil)
      super(message)
      @response = response
    end
  end

  attr_reader :rate_limit_remaining, :rate_limit_reset_at

  def initialize
    @rate_limit_remaining = nil
    @rate_limit_reset_at = nil
    @etag_cache = {}
  end

  # Fetch public events from GitHub
  # @param etag [String, nil] Optional ETag for conditional request
  # @return [Hash] Response with :data (array of events), :etag, :rate_limit_info, :not_modified (boolean)
  def fetch_events(etag: nil)
    response = make_request(:get, EVENTS_ENDPOINT, etag: etag)
    
    {
      data: parse_json(response.body),
      etag: extract_etag(response),
      rate_limit_info: extract_rate_limit_info(response),
      not_modified: false
    }
  rescue NotModifiedError
    # 304 Not Modified - resource hasn't changed, return cached data
    {
      data: [],
      etag: etag,
      rate_limit_info: { remaining: @rate_limit_remaining, reset_at: @rate_limit_reset_at },
      not_modified: true
    }
  rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
    raise NetworkError, "Network error: #{e.message}"
  rescue Faraday::ClientError => e
    handle_client_error(e)
  end

  # Fetch a resource by URL (for actor/repository enrichment)
  # @param url [String] Full URL to the resource
  # @param etag [String, nil] Optional ETag for conditional request
  # @return [Hash] Response with :data, :etag, :rate_limit_info, :not_modified (boolean)
  def fetch_resource(url, etag: nil)
    # Extract path from full URL
    path = URI.parse(url).path
    response = make_request(:get, path, etag: etag)
    
    {
      data: parse_json(response.body),
      etag: extract_etag(response),
      rate_limit_info: extract_rate_limit_info(response),
      not_modified: false
    }
  rescue NotModifiedError
    # 304 Not Modified - resource hasn't changed
    {
      data: nil,
      etag: etag,
      rate_limit_info: { remaining: @rate_limit_remaining, reset_at: @rate_limit_reset_at },
      not_modified: true
    }
  rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
    raise NetworkError, "Network error: #{e.message}"
  rescue Faraday::ClientError => e
    handle_client_error(e)
  end

  # Check if rate limit is approaching
  # @return [Boolean] true if rate limit is low
  def rate_limit_low?(threshold: 10)
    return true if @rate_limit_remaining.nil?
    @rate_limit_remaining <= threshold
  end

  # Check if rate limit is exhausted
  # @return [Boolean] true if rate limit is exhausted
  def rate_limit_exhausted?
    return false if @rate_limit_remaining.nil?
    @rate_limit_remaining <= 0
  end

  # Get seconds until rate limit resets
  # @return [Integer, nil] seconds until reset, or nil if unknown
  def seconds_until_reset
    return nil if @rate_limit_reset_at.nil?
    [(@rate_limit_reset_at - Time.current).to_i, 0].max
  end

  private

  def make_request(method, path, etag: nil)
    check_rate_limit!

    response = connection.send(method) do |req|
      req.url path
      req.headers['Accept'] = 'application/vnd.github+json'
      req.headers['User-Agent'] = 'StrongMind-GitHub-Ingestion/1.0'
      req.headers['If-None-Match'] = etag if etag
    end

    # Handle 304 Not Modified before raise_error middleware processes it
    if response.status == 304
      extract_rate_limit_info(response)
      raise NotModifiedError.new("Resource not modified", response)
    end

    response
  end

  def connection
    @connection ||= Faraday.new(url: BASE_URL) do |conn|
      conn.request :retry, {
        max: 3,
        interval: 0.5,
        interval_randomness: 0.5,
        backoff_factor: 2,
        retry_statuses: [500, 502, 503, 504],
        exceptions: [Faraday::TimeoutError, Faraday::ConnectionFailed]
      }
      conn.response :raise_error, exclude: [304]
      conn.adapter Faraday.default_adapter
    end
  end

  def check_rate_limit!
    if rate_limit_exhausted? && @rate_limit_reset_at
      seconds = seconds_until_reset
      raise RateLimitExceeded, "Rate limit exhausted. Resets in #{seconds} seconds"
    end
  end

  def handle_client_error(error)
    # Handle both Faraday::Response objects and Hash responses (from WebMock)
    response = error.response
    status = response.is_a?(Hash) ? response[:status] : response&.status
    headers = response.is_a?(Hash) ? response[:headers] || {} : response&.headers || {}
    
    case status
    when 403
      if headers['x-ratelimit-remaining'] == '0' || headers['X-RateLimit-Remaining'] == '0'
        update_rate_limit_from_error(error, headers)
        raise RateLimitExceeded, "Rate limit exceeded. Resets at #{@rate_limit_reset_at}"
      else
        raise ApiError, "Forbidden: #{error.message}"
      end
    when 404
      raise ApiError, "Resource not found: #{error.message}"
    when 429
      update_rate_limit_from_error(error, headers)
      raise RateLimitExceeded, "Rate limit exceeded. Resets at #{@rate_limit_reset_at}"
    else
      raise ApiError, "API error (#{status}): #{error.message}"
    end
  end

  def extract_rate_limit_info(response)
    headers = response.headers
    
    remaining = headers['x-ratelimit-remaining']&.to_i
    reset_timestamp = headers['x-ratelimit-reset']&.to_i
    
    @rate_limit_remaining = remaining
    @rate_limit_reset_at = reset_timestamp ? Time.at(reset_timestamp) : nil
    
    {
      remaining: remaining,
      reset_at: @rate_limit_reset_at,
      limit: headers['x-ratelimit-limit']&.to_i
    }
  end

  def update_rate_limit_from_error(error, headers = nil)
    response = error.response
    headers ||= response.is_a?(Hash) ? (response[:headers] || {}) : (response&.headers || {})
    
    # Handle both lowercase and capitalized header keys
    remaining = headers['x-ratelimit-remaining'] || headers['X-RateLimit-Remaining']
    reset_val = headers['x-ratelimit-reset'] || headers['X-RateLimit-Reset']
    
    @rate_limit_remaining = remaining&.to_i || 0
    reset_timestamp = reset_val&.to_i
    @rate_limit_reset_at = reset_timestamp ? Time.at(reset_timestamp) : nil
  end

  def extract_etag(response)
    response.headers['etag']
  end

  def parse_json(body)
    return [] if body.nil? || body.empty?
    JSON.parse(body)
  rescue JSON::ParserError => e
    Rails.logger.error("Failed to parse JSON: #{e.message}")
    raise ApiError, "Invalid JSON response: #{e.message}"
  end
end
