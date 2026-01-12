# Design Brief: GitHub Events Ingestion Service

## The Problem

We need to ingest GitHub's public events API and extract PushEvent data for analytics. The main constraint is GitHub's 60 requests/hour rate limit for unauthenticated access, which is pretty tight. The system needs to run unattended, handle failures gracefully, and not fall over if GitHub's API is slow or rate-limiting us.

From a practical standpoint, this is a data pipeline - reliability and staying within limits matter more than real-time processing. The goal is getting the data ingested and stored, not building a complex real-time system.

## Architecture

I went with a simple service-oriented approach. Each piece has one job:

```
GitHub API → GitHubApiClient → IngestGitHubEventsJob → PushEventParser → Database
                                                              ↓
                                                     EnrichmentService → Database
```

**GitHubApiClient** handles all HTTP stuff - rate limit tracking, ETags, retries with exponential backoff. Keeps the HTTP details out of the rest of the code.

**IngestGitHubEventsJob** orchestrates fetching events, storing raw payloads, filtering for PushEvents, parsing, and storing. Right now it's a rake task, but easy to convert to a scheduled job later.

**PushEventParser** extracts structured fields from the JSON. Has fallbacks for missing fields.

**EnrichmentService** fetches actor/repo details and caches them for 24 hours. This caching is critical for staying within rate limits since we see the same actors and repos repeatedly.

**EnrichPushEventJob** runs enrichment separately so failures don't block ingestion.

The separation makes testing easier - each service can be tested independently. Also makes it easier to reason about what's happening when things go wrong.

## Key Tradeoffs

**Polling vs Webhooks**: Went with polling. Webhooks would require authentication and setup complexity we don't need. Polling is simpler and fine for analytics where real-time isn't required. Trade-off: events arrive within an hour, not instantly. That's acceptable for this use case.

**Async Enrichment**: Enrichment runs separately from ingestion. If GitHub's user/repo APIs are slow or failing, we can still ingest events. The downside is eventual consistency - PushEvents might exist without enriched data for a while. But that's better than enrichment failures blocking all ingestion.

**Database Caching vs Redis**: Used PostgreSQL for caching instead of Redis. One less service to manage, no cache warming issues, survives restarts. Redis would be faster, but for data that changes infrequently, the database is fast enough and simpler to operate.

**Batch vs Streaming**: Everything is batch-oriented. Simpler to build, test, and debug. For analytics, batch processing is the right default. Can always add streaming later if needed.

**Dual Storage**: Store raw payloads in JSONB (or S3 if enabled) plus structured tables. The raw data gives flexibility - can re-parse later if we need new fields. Structured tables make queries fast. Yes, there's duplication, but storage is cheap and query performance matters more.

## Rate Limits and Durability

GitHub's 60 requests/hour limit is the main constraint. I handle it a few ways:

1. **ETag support** - Conditional requests return 304 Not Modified when nothing changed. Saves requests when GitHub's event feed hasn't updated. The ETag is persisted in the database so it survives restarts.

2. **Rate limit tracking** - Monitor `X-RateLimit-Remaining` and `X-RateLimit-Reset` headers. Log the status so you can see what's happening.

3. **Exponential backoff** - When we hit rate limits (429 or 403 with remaining=0), retry with exponentially increasing delays. Jobs are idempotent, so retries are safe.

4. **Caching** - Actor/repository data cached for 24 hours. Dramatically reduces API calls since we see the same actors and repos repeatedly.

For durability: unique constraints on `event_id` and `push_id` prevent duplicates. Jobs use `find_or_initialize_by` patterns to handle races. Status tracking (`processed_at`, `enrichment_status`) lets the system resume after restarts. If a job crashes mid-run, just restart it - won't create duplicates.

The system is designed to be restart-safe. Jobs can be scheduled via cron, Kubernetes jobs, etc., and if they overlap or restart, nothing breaks.

## What I Didn't Build

I kept the scope focused on ingestion and storage. Here's what I skipped and why:

**Real-time Processing** - Batch is simpler and sufficient. Can add streaming later if needed, but starting with streaming adds complexity we don't need.

**Analytics Layer** - This is a data ingestion service. Analytics queries are a separate concern. The structured tables make it easy to build analytics on top.

**User-Facing API** - This is an internal data pipeline. If you need a query API, build it as a separate service that reads from the database.

**Authentication** - Single-tenant internal service. Security can be handled at the infrastructure level (VPC, firewall rules, etc.).

**Horizontal Scaling** - Designed for a single instance. Architecture supports scaling later (stateless jobs, shared database), but premature scaling adds complexity.

**Monitoring Dashboards** - Basic logging and health checks are enough. Dashboards can be added later when we understand what metrics matter.

**Webhook Support** - Would require authentication. Polling is simpler and meets requirements.

**Historical Backfill** - Assumes starting from current events. Historical backfill would be a separate, one-time tool if needed.

The principle here is YAGNI - build what's needed now, add complexity only when there's a clear requirement.
