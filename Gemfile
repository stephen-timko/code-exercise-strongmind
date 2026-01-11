source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby '~> 3.2.0'

# Core Rails framework (API mode)
gem 'rails', '~> 7.1.0'
gem 'puma', '~> 6.0'

# Database
gem 'pg', '~> 1.5'

# JSON parsing and serialization
gem 'jbuilder', '~> 2.11'
gem 'json', '~> 2.6'

# Background jobs
gem 'sidekiq', '~> 7.2'
gem 'redis', '~> 5.0'

# HTTP client for GitHub API
gem 'faraday', '~> 2.0'
gem 'faraday-retry', '~> 2.0'

# Object storage for raw payloads
gem 'aws-sdk-s3', '~> 1.0'

# Utilities
gem 'bootsnap', '>= 1.4.4', require: false
gem 'tzinfo-data', platforms: [:mingw, :mswin, :x64_mingw, :jruby]

# Logging and monitoring
gem 'lograge', '~> 0.13'

group :development, :test do
  gem 'byebug', platforms: [:mri, :mingw, :x64_mingw]
  gem 'rspec-rails', '~> 6.1'
  gem 'factory_bot_rails', '~> 6.2'
  gem 'faker', '~> 3.2'
  gem 'webmock', '~> 3.18'
  gem 'shoulda-matchers', '~> 6.3'
end

group :development do
  gem 'listen', '~> 3.3'
  gem 'spring'
end
