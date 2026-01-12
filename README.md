# GitHub Events Ingestion Service

A service that ingests GitHub Push events from the public events API, enriches them with actor and repository metadata, and stores everything for analytics. Built to run unattended and handle GitHub's rate limits gracefully.

## Quick Start

Prerequisites: Docker Desktop installed and running.

```bash
# Start everything
docker compose up --build

# In another terminal, set up the database
docker compose run --rm web bundle exec rails db:create db:migrate
```

The API server runs on `http://localhost:3000`. Hit `/health` to verify it's up - should return `{"status":"ok"}`.

## Running Ingestion

The ingestion job fetches events from GitHub's public events API, filters for PushEvent types, and stores both raw and structured data:

```bash
docker compose run --rm ingest
```

This will:
- Fetch events from `https://api.github.com/events`
- Filter for PushEvent types only
- Store raw payloads (in JSONB by default, or S3 if enabled)
- Extract structured fields (repository_id, push_id, ref, head, before)
- Create PushEvent records for enrichment

The job uses ETags to avoid re-fetching unchanged data, which helps stay within the 60 requests/hour limit for unauthenticated access. If you hit the rate limit, it retries with exponential backoff - you'll see this in the logs.

## Running Enrichment

Enrichment fetches actor and repository details for PushEvents. It's separate from ingestion so the pipeline keeps running even if enrichment is slow or failing:

```bash
docker compose run --rm web bundle exec rake github:enrich
```

By default it processes 10 events at a time. Adjust with:

```bash
BATCH_SIZE=20 docker compose run --rm web bundle exec rake github:enrich
```

The service caches actor and repository data for 24 hours to avoid hitting API limits. If the cache is stale, it refetches automatically.

## Running Tests

```bash
docker compose run --rm test
```

The test suite uses RSpec and includes:

- **Unit tests** - Services, models, and jobs
- **Integration tests** - End-to-end ingestion and enrichment flows
- **Controller tests** - Health endpoint
- **Edge cases** - Rate limits, network errors, malformed data, idempotency

All external API calls are stubbed using WebMock, so tests run fast and reliably without hitting GitHub's API. The suite includes 194 examples covering:

- GitHub API client (rate limits, ETags, retries, errors)
- Event parsing (valid/invalid data, missing fields, fallbacks)
- Ingestion job (idempotency, filtering, 304 Not Modified)
- Enrichment service (caching, failures, partial enrichment)
- Models (validations, associations, scopes, state transitions)
- Object storage (S3 integration, JSONB fallback)
- End-to-end flows (full pipeline from ingestion to enrichment)

## How to Verify It's Working

After running ingestion, here's how to verify everything is working:

### What Logs to Expect

When you run `docker compose run --rm ingest`, you should see logs like:

```
Starting GitHub events ingestion...
Ingesting 30 events from GitHub API. Rate limit: 50/60
Ingestion complete: 30 events ingested, 12 PushEvents created, 0 errors
Rate limit remaining: 49/60
```

If events haven't changed since the last run, you'll see:
```
GitHub events not modified (304), skipping ingestion
```

If you hit rate limits, you'll see retry messages with exponential backoff delays.

For enrichment, logs look like:
```
Processing 10 pending PushEvents for enrichment...
Enriching PushEvent 1 (push_id: 67890)
Successfully enriched PushEvent 1 (actor: true, repository: true)
```

### What Database Tables or Records to Check

After ingestion, check these tables:

```bash
# Connect to the database
docker compose run --rm web bundle exec rails dbconsole

# Check what was ingested
SELECT COUNT(*) FROM github_events;
SELECT COUNT(*) FROM push_events;

# See some actual events
SELECT event_id, event_type, ingested_at, processed_at FROM github_events LIMIT 5;
SELECT repository_id, push_id, ref, enrichment_status FROM push_events LIMIT 5;

# Check enrichment status
SELECT enrichment_status, COUNT(*) FROM push_events GROUP BY enrichment_status;
```

You should see:
- `github_events` table with raw event payloads (or `s3_key` if S3 is enabled)
- `push_events` table with structured data (repository_id, push_id, ref, head, before)
- `actors` and `repositories` tables populated after enrichment runs

### How Long Before Results Appear

- **Ingestion**: Results appear immediately after the job completes (usually 5-30 seconds depending on how many events GitHub returns)
- **Enrichment**: Run separately after ingestion. Each batch of 10 events takes about 10-20 seconds, depending on API response times and cache hits

If you don't see results:
- Check the logs for rate limit messages - you might have hit the 60 requests/hour limit
- Verify the database connection: `docker compose ps` should show all services running
- Check for errors in logs: `docker compose logs ingest` or `docker compose logs web`

## Optional: S3 Storage

By default, raw event payloads are stored in PostgreSQL JSONB columns. If you want to offload them to S3 (useful for compliance or reducing database size), set these environment variables:

```bash
AWS_S3_ENABLED=true
AWS_S3_BUCKET=your-bucket-name
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=your-key
AWS_SECRET_ACCESS_KEY=your-secret
```

The service automatically stores payloads in S3 when enabled, with keys like `events/2026/01/15/12345.json`. If S3 is disabled or fails, it falls back to JSONB storage. The `github_events` table tracks which storage method was used via the `s3_key` column.

For local development with S3, you can use LocalStack by setting `AWS_ENDPOINT=http://localhost:4566`.

## Checking Status

The stats task gives you a quick overview:

```bash
docker compose run --rm web bundle exec rake github:stats
```

This shows event counts, enrichment status, and success rates. Useful for seeing how the pipeline is performing.

## Development

Standard Rails commands work through Docker:

```bash
# Rails console
docker compose run --rm web bundle exec rails console

# Run migrations
docker compose run --rm web bundle exec rails db:migrate

# View logs
docker compose logs -f web
docker compose logs -f ingest

# Run tests
docker compose run --rm test
```

## Architecture

The system uses a service-oriented architecture where each component has a clear responsibility:

- `GitHubApiClient` - Handles HTTP communication with rate limit tracking
- `PushEventParser` - Extracts structured data from raw payloads
- `EnrichmentService` - Manages fetching and caching of actor/repository data
- Jobs orchestrate the ingestion and enrichment flows

Raw events are stored for auditability, while structured data goes into normalized tables for efficient querying. This dual-storage approach gives us flexibility: we can always parse the raw JSON if we need new fields, but structured queries are fast without JSON parsing.

Enrichment is decoupled from ingestion so the pipeline can keep ingesting even if enrichment fails. Status tracking (`enrichment_status`) lets us resume from where we left off after restarts or failures.

For more details on design decisions and trade-offs, see `DESIGN_BRIEF.md`.

## Troubleshooting

**No events ingested:**
Check the logs for rate limit status. The job logs rate limit headers on each request. If you've hit the limit, wait an hour or run the job later. The system uses ETags to avoid unnecessary requests, so subsequent runs should be faster.

**Enrichment failures:**
Most enrichment failures are due to rate limits or network issues. The service marks events as failed after retries, so you can manually retry them later. Check logs for specific error messages.

**Database connection errors:**
Make sure PostgreSQL is running: `docker compose ps`. You can check database health with: `docker compose exec db pg_isready -U postgres`

**ETag not working:**
The ETag is stored in the `job_states` table. If you're not seeing 304 responses, check that the `job_states` table exists and has a record with key `github_events_etag`.
