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
- Start Redis for background jobs
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

## How to Run Ingestion

To ingest GitHub events from the public events API:

```bash
docker compose run --rm ingest
```

This will:
- Fetch events from `https://api.github.com/events`
- Filter for PushEvent type only
- Store raw events in the `github_events` table
- Parse and store structured PushEvent data in the `push_events` table
- Handle rate limits gracefully (60 requests/hour unauthenticated)
- Use ETag-based conditional requests to reduce bandwidth

**Expected output:**
```
Starting GitHub events ingestion...
Ingesting 30 events from GitHub API. Rate limit: 45/60
Ingestion complete: 30 events ingested, 5 PushEvents created, 0 errors
Rate limit remaining: 45/60
Ingestion completed successfully
```

**Note:** The ingestion respects GitHub's rate limits. If you hit the limit, the job will retry with exponential backoff.

## How to Run Enrichment

To enrich pending PushEvents with actor and repository data:

```bash
docker compose run --rm web rake github:enrich
```

Or with a custom batch size:

```bash
BATCH_SIZE=20 docker compose run --rm web rake github:enrich
```

This will:
- Find pending PushEvents (up to the batch size, default: 10)
- Fetch actor and repository data from GitHub API
- Cache enriched data to avoid unnecessary refetches
- Link enriched data to PushEvents
- Update enrichment status

**Expected output:**
```
Starting enrichment of pending PushEvents...
Processing 5 pending PushEvents...
  ✓ Enriched PushEvent 1
  ✓ Enriched PushEvent 2
  ✓ Enriched PushEvent 3
  ✓ Enriched PushEvent 4
  ✓ Enriched PushEvent 5

Enrichment completed: 5 succeeded, 0 failed
```

## How to Verify It's Working

### 1. Check Logs

View the application logs to see ingestion and enrichment activity:

```bash
docker compose logs -f web
```

**Expected log patterns:**

**During ingestion:**
```
INFO -- : Ingesting 30 events from GitHub API. Rate limit: 45/60
INFO -- : Ingestion complete: 30 events ingested, 5 PushEvents created, 0 errors
INFO -- : Rate limit remaining: 45/60
```

**During enrichment:**
```
INFO -- : Enriching PushEvent 1 (push_id: 12345)
INFO -- : Successfully enriched PushEvent 1 (actor: true, repository: true)
```

**On errors:**
```
ERROR -- : Failed to parse PushEvent from event 12345: Missing required fields: push_id
ERROR -- : Failed to enrich PushEvent 2: Network error: Connection timeout
```

### 2. Check Database Tables

Connect to the database and verify data:

```bash
docker compose run --rm web rails dbconsole
```

**Check raw events:**
```sql
SELECT COUNT(*) FROM github_events;
SELECT event_type, COUNT(*) FROM github_events GROUP BY event_type;
SELECT * FROM github_events WHERE event_type = 'PushEvent' LIMIT 5;
```

**Check structured PushEvents:**
```sql
SELECT COUNT(*) FROM push_events;
SELECT repository_id, COUNT(*) FROM push_events GROUP BY repository_id;
SELECT * FROM push_events LIMIT 5;
```

**Check enrichment data:**
```sql
SELECT COUNT(*) FROM actors;
SELECT COUNT(*) FROM repositories;
SELECT 
  pe.id, 
  pe.repository_id, 
  pe.push_id,
  pe.enrichment_status,
  a.login as actor_login,
  r.full_name as repo_full_name
FROM push_events pe
LEFT JOIN actors a ON pe.actor_id = a.id
LEFT JOIN repositories r ON pe.enriched_repository_id = r.id
LIMIT 10;
```

### 3. Use the Stats Rake Task

Get a quick overview of system statistics:

```bash
docker compose run --rm web rake github:stats
```

**Expected output:**
```
=== GitHub Events Ingestion Statistics ===

Total Events: 150
Push Events: 25
Processed Events: 25
Unprocessed Events: 0

--- Push Events ---
Total Push Events: 25
Enriched: 20
Pending Enrichment: 3
Failed Enrichment: 2

--- Enrichment Data ---
Actors: 15
Repositories: 12

Enrichment Rate: 80.0%

==========================================
```

### 4. Expected Timeline

- **First ingestion:** Should see events within 1-2 minutes
- **PushEvents created:** Immediately after ingestion completes
- **Enrichment:** Should complete within 30 seconds for a batch of 10 events
- **Rate limits:** System will wait and retry if rate limit is hit (typically resets every hour)

### 5. Verification Checklist

- [ ] Health endpoint returns `{"status":"ok"}`
- [ ] Ingestion completes without errors
- [ ] `github_events` table has records
- [ ] `push_events` table has records with `event_type = 'PushEvent'`
- [ ] Logs show successful ingestion messages
- [ ] Enrichment completes successfully
- [ ] `actors` and `repositories` tables have records
- [ ] PushEvents show `enrichment_status = 'completed'` after enrichment
- [ ] Stats task shows expected counts

## Project Structure

```
.
├── app/
│   ├── controllers/     # API controllers (health check)
│   ├── jobs/            # Background jobs (ingestion, enrichment)
│   ├── models/          # ActiveRecord models
│   └── services/        # Service classes (API client, parser, enrichment)
├── config/              # Rails configuration
├── db/
│   └── migrate/         # Database migrations
├── lib/
│   └── tasks/           # Rake tasks (ingest, enrich, stats)
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

### Running tests (if implemented)

```bash
docker compose run --rm test
```

This will:
- Run RSpec test suite
- Use the test database (separate from development)
- Execute all tests and report results

## Technology Stack

- **Ruby**: 3.2.0
- **Rails**: 7.1 (API mode)
- **PostgreSQL**: 15
- **Sidekiq**: Background job processing
- **Redis**: Job queue backend
- **Faraday**: HTTP client for GitHub API

## Key Features

- **Rate Limit Awareness**: Tracks and respects GitHub's 60 req/hour unauthenticated limit
- **ETag Support**: Uses conditional requests to reduce bandwidth
- **Idempotency**: Safe to run multiple times without duplicate data
- **Enrichment Caching**: Avoids unnecessary API calls for actor/repository data
- **Error Handling**: Graceful handling of malformed data and API failures
- **Observability**: Comprehensive logging for debugging and monitoring

## Architecture

The system follows a service-oriented architecture:

1. **Ingestion**: `IngestGitHubEventsJob` fetches events and stores raw + structured data
2. **Parsing**: `PushEventParser` extracts structured fields from raw event payloads
3. **Enrichment**: `EnrichmentService` fetches and caches actor/repository data
4. **Storage**: PostgreSQL with JSONB for raw data, structured tables for querying

## Rate Limiting Strategy

- Tracks `X-RateLimit-Remaining` and `X-RateLimit-Reset` headers
- Exponential backoff on rate limit errors
- ETag-based conditional requests to minimize API calls
- Queue management to prevent exceeding limits

## Troubleshooting

**No events ingested:**
- Check rate limit status in logs
- Verify GitHub API is accessible
- Check network connectivity

**Enrichment failing:**
- Verify actor/repository URLs in event payloads
- Check rate limit status
- Review error logs for specific failures

**Database connection errors:**
- Ensure database service is running: `docker compose ps`
- Check database health: `docker compose exec db pg_isready -U postgres`
