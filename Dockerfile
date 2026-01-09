FROM ruby:3.2-alpine

# Install system dependencies
RUN apk add --no-cache \
    build-base \
    postgresql-dev \
    postgresql-client \
    yaml-dev \
    git \
    curl \
    tzdata \
    nodejs \
    yarn

# Set working directory
WORKDIR /app

# Install bundler
RUN gem install bundler -v 2.4.22

# Copy Gemfile and Gemfile.lock
COPY Gemfile Gemfile.lock* ./

# Install gems
RUN bundle install

# Copy application code
COPY . .

# Expose port
EXPOSE 3000

# Default command (can be overridden in docker-compose.yml)
CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0", "-p", "3000"]
