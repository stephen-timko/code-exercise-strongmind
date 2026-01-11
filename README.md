# GitHub Events Ingestion Service

This service ingests GitHub Push events from the public events API, enriches them with actor and repository metadata, and stores the data for analytics. It's designed to run unattended, handle failures gracefully, and respect GitHub's rate limits.

## Getting Started

Make sure you have Docker Desktop installed, then:

```bash
docker compose up --build
```

This starts PostgreSQL, Redis, and the Rails API server. Once it's up, set up the database:

```bash
docker compose run --rm web bundle exec rails db:create db:migrate
```

The health endpoint should return `{"status":"ok"}` when you hit `http://localhost:3000/health`.

## Running Ingestion

The ingestion job fetches events from GitHub's public events API, filters for PushEvent types, and stores both raw and structured data:

```bash
docker compose run --rm ingest
```

You'll see output showing how many events were ingested and the current rate limit status. The job uses ETags to avoid re-fetching unchanged data, which helps stay within the 60 requests/hour limit for unauthenticated access.

If you hit the rate limit, the job will retry with exponential backoff. The logs will show when this happens.

## Running Enrichment

Enrichment fetches actor and repository details for PushEvents. It's designed to run as a separate process so ingestion can continue even if enrichment is slow or failing:

```bash
docker compose run --rm web bundle exec rake github:enrich
```

By default it processes 10 events at a time. You can adjust this with:

```bash
BATCH_SIZE=20 docker compose run --rm web bundle exec rake github:enrich
```

The service caches actor and repository data for 24 hours to avoid hitting API limits. If the cache is stale, it refetches automatically.

## Checking Status

The stats task gives you a quick overview:

```bash
docker compose run --rm web bundle exec rake github:stats
```

This shows event counts, enrichment status, and success rates. Useful for seeing how the pipeline is performing.

You can also check the database directly:

```bash
docker compose run --rm web bundle exec rails dbconsole
```

The key tables are:
- `github_events` - Raw event payloads (JSONB, or optionally stored in S3)
- `push_events` - Structured PushEvent data
- `actors` - Cached actor data
- `repositories` - Cached repository data

## Optional: S3 Storage

By default, raw event payloads are stored in PostgreSQL JSONB columns. If you want to offload them to S3 (useful for compliance or reducing database size), set:

```bash
AWS_S3_ENABLED=true
AWS_S3_BUCKET=your-bucket-name
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=your-key
AWS_SECRET_ACCESS_KEY=your-secret
```

The service automatically stores payloads in S3 when enabled, with keys like `events/2026/01/15/12345.json`. If S3 is disabled or fails, it falls back to JSONB storage. The `github_events` table tracks which storage method was used via the `s3_key` column.

For local development with S3, you can use LocalStack by setting `AWS_ENDPOINT=http://localhost:4566`.

## Development

Standard Rails commands work through Docker:

```bash
# Rails console
docker compose run --rm web bundle exec rails console

# Run migrations
docker compose run --rm web bundle exec rails db:migrate

# View logs
docker compose logs -f web

# Run tests
docker compose run --rm test
```

The test suite uses RSpec and includes unit tests, integration tests, and end-to-end flows. All external API calls are stubbed using WebMock.

## Architecture Notes

The system uses a service-oriented architecture where each component has a clear responsibility:

- `GitHubApiClient` handles HTTP communication with rate limit tracking
- `PushEventParser` extracts structured data from raw payloads
- `EnrichmentService` manages fetching and caching of actor/repository data
- Jobs orchestrate the ingestion and enrichment flows

Raw events are stored for auditability, while structured data goes into normalized tables for efficient querying. This dual-storage approach gives us flexibility: we can always parse the raw JSON if we need new fields, but structured queries are fast without JSON parsing.

Enrichment is decoupled from ingestion so the pipeline can keep ingesting even if enrichment fails. Status tracking (`enrichment_status`) lets us resume from where we left off after restarts or failures.

For more details on design decisions and trade-offs, see DESIGN_BRIEF.md.

## Troubleshooting

**No events ingested:**
Check the logs for rate limit status. The job logs rate limit headers on each request. If you've hit the limit, wait an hour or run the job later.

**Enrichment failures:**
Most enrichment failures are due to rate limits or network issues. The service marks events as failed after retries, so you can manually retry them later. Check logs for specific error messages.

**Database connection errors:**
Make sure PostgreSQL is running: `docker compose ps`. You can check database health with: `docker compose exec db pg_isready -U postgres`
