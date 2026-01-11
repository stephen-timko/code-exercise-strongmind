# Object Storage (S3) Configuration
# Configured via environment variables for flexibility across environments

module ObjectStorage
  module Config
    # AWS credentials
    ACCESS_KEY_ID = ENV.fetch('AWS_ACCESS_KEY_ID', nil)
    SECRET_ACCESS_KEY = ENV.fetch('AWS_SECRET_ACCESS_KEY', nil)
    
    # AWS region (default: us-east-1)
    REGION = ENV.fetch('AWS_REGION', 'us-east-1')
    
    # S3 bucket name
    BUCKET = ENV.fetch('AWS_S3_BUCKET', 'strongmind-github-events')
    
    # Custom endpoint (useful for localstack or compatible services)
    ENDPOINT = ENV.fetch('AWS_ENDPOINT', nil)
    
    # Enable/disable object storage (fallback to JSONB if disabled)
    ENABLED = ENV.fetch('AWS_S3_ENABLED', 'false').casecmp?('true')
  end
end
