# StrongMind GitHub Events Ingestion Service

A Rails API service that ingests GitHub Push events from the public events API, enriches them with related data, and stores them for future querying and analysis.

## Prerequisites

- Docker Desktop for macOS
- Git

## Getting Started

### 1. Start the system

```bash
docker compose up --build
```

This will:
- Build the Rails API application
- Start PostgreSQL database
- Start the Rails server on port 3000

### 2. Set up the database

In a new terminal, run:

```bash
docker compose run --rm web rails db:create db:migrate
```

### 3. Verify the system is running

```bash
curl http://localhost:3000/health
```

You should see:
```json
{"status":"ok","timestamp":"2024-01-01T12:00:00Z"}
```

## Project Structure

```
.
├── app/
│   ├── controllers/     # API controllers
│   ├── jobs/            # Background jobs
│   └── models/          # ActiveRecord models
├── config/              # Rails configuration
├── db/                  # Database migrations and schema
├── docker-compose.yml   # Docker Compose configuration
├── Dockerfile          # Rails application Docker image
└── README.md           # This file
```

## Development

### Running Rails console

```bash
docker compose run --rm web rails console
```

### Running database migrations

```bash
docker compose run --rm web rails db:migrate
```

### Viewing logs

```bash
docker compose logs -f web
```

## Technology Stack

- **Ruby**: 3.2.0
- **Rails**: 7.1 (API mode)
- **PostgreSQL**: 15
- **Sidekiq**: Background job processing
- **Faraday**: HTTP client for GitHub API

## Next Steps

This is the initial setup. The following features will be implemented:
- GitHub events ingestion
- Push event parsing and storage
- Actor and repository enrichment
- Rate limiting and error handling
- Observability and logging
