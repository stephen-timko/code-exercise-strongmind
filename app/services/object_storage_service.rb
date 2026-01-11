# Object Storage Service for S3 Integration
# Handles storage and retrieval of raw event payloads in S3
# Falls back to JSONB storage when S3 is disabled

class ObjectStorageService
  class StorageError < StandardError; end
  class NotFoundError < StorageError; end

  # Store a payload in S3 (if enabled) or return nil (use JSONB fallback)
  # @param event_id [String] The event ID (used to generate S3 key)
  # @param payload [Hash] The payload to store
  # @return [String, nil] S3 key if stored in S3, nil if using JSONB fallback
  def self.store(event_id, payload)
    return nil unless ObjectStorage::Config::ENABLED

    new.store(event_id, payload)
  end

  # Retrieve a payload from S3
  # @param key [String] The S3 key
  # @return [Hash] The payload
  # @raise [NotFoundError] if key doesn't exist in S3
  # @raise [StorageError] if retrieval fails
  def self.retrieve(key)
    new.retrieve(key)
  end

  # Delete a payload from S3
  # @param key [String] The S3 key
  # @return [Boolean] true if deleted, false if not found or disabled
  def self.delete(key)
    return false unless ObjectStorage::Config::ENABLED

    new.delete(key)
  end

  def initialize
    @s3_client = build_s3_client if ObjectStorage::Config::ENABLED
  end

  def store(event_id, payload)
    key = generate_key(event_id)
    body = JSON.generate(payload)

    @s3_client.put_object(
      bucket: ObjectStorage::Config::BUCKET,
      key: key,
      body: body,
      content_type: 'application/json'
    )

    Rails.logger.debug("Stored event #{event_id} in S3: #{key}")
    key
  rescue Aws::S3::Errors::ServiceError => e
    Rails.logger.error("Failed to store event #{event_id} in S3: #{e.message}")
    raise StorageError, "S3 storage failed: #{e.message}"
  end

  def retrieve(key)
    response = @s3_client.get_object(
      bucket: ObjectStorage::Config::BUCKET,
      key: key
    )

    JSON.parse(response.body.read)
  rescue Aws::S3::Errors::NoSuchKey
    raise NotFoundError, "S3 key not found: #{key}"
  rescue Aws::S3::Errors::ServiceError => e
    Rails.logger.error("Failed to retrieve key #{key} from S3: #{e.message}")
    raise StorageError, "S3 retrieval failed: #{e.message}"
  end

  def delete(key)
    @s3_client.delete_object(
      bucket: ObjectStorage::Config::BUCKET,
      key: key
    )

    Rails.logger.debug("Deleted key from S3: #{key}")
    true
  rescue Aws::S3::Errors::NoSuchKey
    Rails.logger.debug("Key not found in S3 (already deleted): #{key}")
    false
  rescue Aws::S3::Errors::ServiceError => e
    Rails.logger.error("Failed to delete key #{key} from S3: #{e.message}")
    raise StorageError, "S3 deletion failed: #{e.message}"
  end

  private

  def build_s3_client
    config = {
      region: ObjectStorage::Config::REGION,
      credentials: build_credentials
    }

    # Add custom endpoint if configured (for localstack, etc.)
    if ObjectStorage::Config::ENDPOINT.present?
      config[:endpoint] = ObjectStorage::Config::ENDPOINT
      config[:force_path_style] = true # Required for localstack
    end

    Aws::S3::Client.new(config)
  end

  def build_credentials
    access_key_id = ObjectStorage::Config::ACCESS_KEY_ID
    secret_access_key = ObjectStorage::Config::SECRET_ACCESS_KEY

    if access_key_id.present? && secret_access_key.present?
      Aws::Credentials.new(access_key_id, secret_access_key)
    else
      # Use default credential provider chain (IAM roles, env vars, etc.)
      Aws::Credentials.new(nil, nil)
    end
  end

  def generate_key(event_id)
    # Generate S3 key: events/{event_id}.json
    # Using timestamp prefix for better S3 partitioning
    timestamp = Time.current.strftime('%Y/%m/%d')
    "events/#{timestamp}/#{event_id}.json"
  end
end
