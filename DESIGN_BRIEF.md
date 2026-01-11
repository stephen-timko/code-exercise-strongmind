# Design Brief: GitHub Events Ingestion Service

## The Problem We're Solving

This service provides visibility into GitHub activity to support analytics on repository usage and contributor behavior. The goal is a reliable data pipeline that can run unattended, handle failures gracefully, and respect GitHub's strict rate limits for unauthenticated access (60 requests/hour).

From a business perspective, this enables data-driven decisions about repository usage patterns, contributor activity, and platform adoption. The technical challenge is building something reliable enough to run in production without constant babysitting, while staying within tight API constraints.

## Architecture Overview

The system follows a straightforward service-oriented design where each component has a single, well-defined responsibility:

```
GitHub API → API Client → Ingestion Job → Parser → Database
                                    ↓
                            Enrichment Service → Database
```

This separation makes the code easy to test, reason about, and modify. Each service can be developed and tested independently, which speeds up development and reduces bugs.

**Components:**

1. **GitHubApiClient** - Handles all HTTP communication with GitHub. Tracks rate limits, manages ETags for conditional requests, and implements retry logic with exponential backoff. This encapsulation means the rest of the system doesn't need to know about rate limit headers or HTTP details.

2. **IngestGitHubEventsJob** - Orchestrates the ingestion flow: fetch events, store raw payloads, filter for PushEvents, parse structured data, and store it. Runs as a rake task for now, but designed so it could easily become a scheduled job.

3. **PushEventParser** - Extracts structured fields from raw event JSON. Handles missing fields gracefully with fallbacks. This keeps parsing logic isolated from storage concerns.

4. **EnrichmentService** - Manages fetching and caching of actor and repository data. The caching is crucial for staying within rate limits - actor/repository data doesn't change often, so we cache for 24 hours.

5. **EnrichPushEventJob** - Processes enrichment asynchronously. Designed so enrichment failures don't block ingestion.

## Data Storage Strategy

I chose a dual-storage approach: raw JSONB for auditability, structured tables for efficient querying. This is a common pattern in data pipelines, and for good reason.

**Why both?**

The raw JSONB gives us flexibility. If we need a new field later, we can re-parse the raw payloads without re-ingesting from GitHub. It also serves as an audit trail. The structured tables (`push_events`) make queries fast - no JSON parsing needed, proper indexes, and normalized data for joins.

Yes, there's some data duplication, but storage is cheap and query performance matters more for analytics workloads. The structured tables are also easier for analysts to work with - they don't need to understand JSONB queries.

**Optional S3 Storage**

For production deployments with large volumes, storing raw payloads in S3 can make sense. It reduces database size and cost, and S3 is durable and compliant-friendly. The implementation is designed as a feature flag - when enabled, payloads go to S3 and the `github_events` table stores just the S3 key. When disabled (default), it uses JSONB. The code handles both paths transparently.

## Key Design Decisions

### Polling vs Webhooks

I chose polling because we're using the public events API without authentication. Webhooks would require authentication and setup complexity we don't need. Polling is simpler, more predictable, and perfectly adequate for analytics workloads where real-time isn't required.

The trade-off is we're not getting events the instant they happen, but for analytics that's fine. We get them within an hour at worst.

### Async Enrichment

Enrichment runs separately from ingestion so failures don't block the main pipeline. If GitHub's user/repo APIs are slow or failing, we can still ingest events. The enrichment status tracking lets us resume later.

The trade-off is eventual consistency - PushEvents might exist without enriched data for a while. But this is much better than the alternative where a failing enrichment step blocks all ingestion.

### Database Caching vs Redis

I used PostgreSQL for caching actor/repository data instead of Redis. This simplifies the architecture - one fewer service to manage, no cache warming issues, durable across restarts. Redis would be faster, but for this use case (caching data that changes infrequently) the database is fast enough and the operational simplicity wins.

### Batch Processing

Everything is batch-oriented rather than streaming. This is simpler to build, test, and debug. For analytics workloads, batch processing is the right default. We can always add streaming later if needed, but starting with streaming adds complexity we don't need yet.

## Rate Limiting Strategy

GitHub's 60 requests/hour limit for unauthenticated access is the main constraint. We handle this through:

1. **ETag support** - Conditional requests that return 304 Not Modified when nothing changed. This saves requests when GitHub's event feed hasn't updated.

2. **Header tracking** - We monitor `X-RateLimit-Remaining` and `X-RateLimit-Reset` on every response. This lets us know when we're getting close to the limit.

3. **Exponential backoff** - When we hit rate limits (429 or 403 with remaining=0), we retry with exponentially increasing delays. Jobs are designed to be idempotent, so retries are safe.

4. **Caching** - Actor/repository data is cached for 24 hours. This dramatically reduces API calls since we typically see the same actors and repos repeatedly.

The system logs rate limit status so operators can see what's happening. In production, you'd want to alert if we're consistently hitting limits, which might indicate we need authenticated access or a different strategy.

## Idempotency and Restart Safety

The system is designed to be restart-safe. Unique constraints on `event_id` and `push_id` prevent duplicates. Jobs use `find_or_initialize_by` patterns to handle races safely. If a job crashes mid-run, you can just restart it - it won't create duplicates.

Status tracking (`processed_at`, `enrichment_status`) lets the system resume from where it left off. Events can be in various states (pending, in_progress, completed, failed), so partial runs are handled gracefully.

This idempotency is crucial for production reliability. Jobs can be scheduled via cron, Kubernetes jobs, or similar, and if they overlap or restart, nothing breaks.

## What I Didn't Build (And Why)

I intentionally kept the scope focused on data ingestion and storage. Here's what I left out and why:

**Real-time Processing** - Batch processing is simpler and sufficient for analytics. If real-time becomes a requirement later, we can add it, but starting with streaming adds complexity we don't need.

**Analytics Layer** - This is a data ingestion service. Analytics queries are a separate concern. The structured tables make it easy to build analytics on top, but that's outside this service's scope.

**User-Facing API** - This is an internal data pipeline. If you need a query API, build it as a separate service that reads from the database. This keeps responsibilities clear.

**Authentication** - Single-tenant internal service. Security can be handled at the infrastructure level (VPC, firewall rules, etc.). Adding auth here adds complexity without clear benefit for this use case.

**Horizontal Scaling** - Designed for a single instance. The architecture supports scaling later (stateless jobs, shared database), but premature scaling adds complexity. Start simple, scale when needed.

**Monitoring Dashboards** - Basic logging and health checks are enough to start. Dashboards can be added later when we understand what metrics matter. Over-instrumenting early is wasteful.

**Webhook Support** - Would require authentication and webhook setup. Polling is simpler and meets current requirements.

**Historical Backfill** - Assumes starting from current events. Historical backfill would be a separate, one-time migration tool if needed. Not worth building into the main pipeline.

**Advanced Deduplication** - Database unique constraints handle deduplication at the scale we're targeting. More sophisticated approaches (Bloom filters, event sourcing) add complexity without clear benefit.

**Config Management** - Environment variables are sufficient for now. When we need more sophisticated config (multiple environments, secret management), we can add it. But not before we need it.

The principle here is YAGNI (You Aren't Gonna Need It). Build what's needed now, add complexity only when there's a clear requirement.

## Testing Strategy

I built a comprehensive test suite because data pipelines are hard to debug in production. The tests cover:

- Unit tests for each service, model, and job
- Integration tests for end-to-end flows
- Edge cases: network failures, rate limits, malformed data
- Idempotency: ensuring jobs can run multiple times safely

External API calls are stubbed using WebMock, so tests run fast and reliably. FactoryBot generates realistic test data.

The test suite runs in about 27 seconds with 181 examples. This fast feedback loop makes development faster and catches bugs before production.

## Business Considerations

From a business perspective, this design prioritizes:

**Operational Simplicity** - Fewer moving parts means fewer things that can break. The architecture is straightforward enough that a new engineer can understand it quickly.

**Cost Efficiency** - Using PostgreSQL for caching instead of Redis saves infrastructure cost. Batch processing instead of streaming reduces complexity and operational overhead.

**Reliability** - Idempotency and restart safety mean the system can recover from failures without manual intervention. This reduces operational burden.

**Time to Market** - The scope is focused on what's needed now. We can add features (streaming, dashboards, etc.) later when requirements are clearer.

**Future Flexibility** - The dual-storage approach and service-oriented design make it easy to add features later without rewrites. We're not painting ourselves into corners.

The goal is a system that works reliably, is easy to operate, and can evolve as requirements change. These aren't just technical decisions - they're business decisions about where to invest engineering time and infrastructure dollars.

## Moving Forward

If I were to extend this system, my priorities would be:

1. **Monitoring and Alerting** - Add metrics (Prometheus, DataDog, etc.) and alerts for rate limit issues, enrichment failures, and data freshness.

2. **Data Quality Checks** - Validate data completeness, freshness, and schema changes. Catch issues before they impact downstream analytics.

3. **Performance Optimization** - As data volumes grow, optimize queries, add indexes, and consider partitioning strategies.

4. **Operational Tooling** - CLI tools for manual retries, data inspection, and troubleshooting. Reduces the need for database access.

5. **Schema Evolution** - Plan for how to handle schema changes as GitHub's API evolves. Version the raw payloads and handle migrations gracefully.

But all of that can wait until we have real requirements and real data volumes. The current design gets us started while leaving room to grow.
