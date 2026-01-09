# Design Brief: GitHub Events Ingestion Service

## Problem Understanding

This service provides visibility into GitHub activity to support analytics on repository usage and contributor behavior. The system implements a reliable, unattended data pipeline that:

1. **Ingests** GitHub Push events from the public events API (unauthenticated, rate-limited)
2. **Transforms** raw events into structured, queryable data
3. **Enriches** events with related actor and repository metadata
4. **Persists** data durably for future analysis

The system operates unattended, handles failures gracefully, and respects GitHub's rate limits (60 requests/hour unauthenticated). As an internal data pipeline, architectural decisions prioritize reliability and maintainability.

## Proposed Architecture

### Component Overview

The system follows a service-oriented architecture with clear separation of concerns:

```
GitHub API → API Client → Ingestion Job → Parser → Database
                                    ↓
                            Enrichment Service → Database
```

**Key Components:**

1. **GitHubApiClient** - HTTP client abstraction with rate limit awareness, ETag support, and retry logic
2. **IngestGitHubEventsJob** - Orchestrates event fetching, filtering, and storage
3. **PushEventParser** - Transforms raw JSON payloads into structured data
4. **EnrichmentService** - Fetches and caches actor/repository data
5. **EnrichPushEventJob** - Async enrichment processing

### Data Flow

1. **Ingestion**: Fetch events → Store raw → Filter PushEvents → Parse → Store structured
2. **Enrichment**: Find pending → Check cache → Fetch if stale → Link to PushEvents
3. **Storage**: Dual-layer approach (raw JSONB + structured tables) for flexibility and query performance

### Database Design

- **github_events**: Raw event storage with JSONB for audit trail
- **push_events**: Structured queryable fields (repository_id, push_id, ref, head, before)
- **actors** & **repositories**: Enrichment cache with TTL-based freshness checks
- Unique constraints ensure idempotency at the database level

## Key Tradeoffs and Assumptions

### Tradeoffs

**1. Polling vs Webhooks**
- **Chosen**: Polling (public events API)
- **Rationale**: No authentication means no webhook registration. Polling is simpler, predictable, and sufficient for the use case. Tradeoff: Less real-time, but acceptable for analytics workloads.

**2. Synchronous vs Async Enrichment**
- **Chosen**: Async (background jobs)
- **Rationale**: Enrichment can fail independently without blocking ingestion. Allows ingestion to proceed even if enrichment is slow or failing. Tradeoff: Eventual consistency, but acceptable for analytics.

**3. Database Caching vs External Cache**
- **Chosen**: Database as persistent cache
- **Rationale**: Simpler architecture, no additional infrastructure, durable across restarts. Tradeoff: Slightly slower than Redis, but sufficient for enrichment caching.

**4. Structured Tables vs JSON-only**
- **Chosen**: Dual storage (raw JSONB + structured tables)
- **Rationale**: JSONB provides flexibility for future fields, structured tables enable efficient queries without JSON parsing. Tradeoff: Some data duplication, acceptable for query performance.

### Assumptions

1. **Historical data not required** - System starts from current events, no backfill needed
2. **Event ordering not critical** - Analytics can tolerate eventual consistency
3. **Partial enrichment acceptable** - System continues operating if actor or repository enrichment fails
4. **Single instance sufficient** - No horizontal scaling requirements for initial implementation
5. **24-hour cache TTL** - Actor/repository data changes infrequently, daily refresh is sufficient

## Rate Limiting and Durability

### Rate Limiting Strategy

**Constraint**: 60 requests/hour unauthenticated (hard limit)

**Approach**:
1. **Header Tracking**: Monitor `X-RateLimit-Remaining` and `X-RateLimit-Reset` headers
2. **ETag Optimization**: Use conditional requests (`If-None-Match`) to avoid unnecessary data transfer when events haven't changed
3. **Polynomial Backoff**: Retry with polynomially increasing delays on rate limit errors (429, 403 with remaining=0)
4. **Pre-request Checks**: Verify rate limit status before making requests
5. **Queue Management**: Process events in batches, respect rate limits between batches

**Behavior Under Rate Limiting**:
- Jobs retry with polynomial backoff (polynomially increasing delays, up to 3 attempts)
- System logs rate limit status for visibility
- Graceful degradation with retry logic prevents crash loops
- Rate limit information tracked and logged for observability

### Durability Approach

**Idempotency**:
- Unique constraints on `event_id` (github_events) and `push_id` (push_events)
- `find_or_initialize_by` patterns prevent duplicate processing
- Race condition handling with `RecordNotUnique` rescue
- Safe to restart or run multiple times without data corruption

**Data Persistence**:
- All raw events stored in `github_events` table (JSONB)
- Structured data in `push_events` table with foreign key relationships
- Enrichment data cached in `actors` and `repositories` tables
- Database transactions ensure atomicity

**Restart Safety**:
- Idempotent operations allow safe restarts
- Status tracking (`processed_at`, `enrichment_status`) enables resume from last state
- No unbounded growth: unique constraints prevent duplicates
- Partial state handling: events can be in various states (pending, in_progress, completed, failed)

## What I Intentionally Did Not Build

**1. Real-time Processing**
- Uses batch processing instead of streaming. Analytics workloads don't require real-time data, and batch processing is simpler and more reliable.

**2. Complex Analytics Layer**
- Focused on data ingestion and storage. Analytics queries are outside the scope of this ingestion service.

**3. User-facing API**
- Internal service only. No REST API for querying data (can be added later if needed).

**4. Authentication/Authorization**
- Single-tenant internal service. Security can be handled at the infrastructure level if needed.

**5. Horizontal Scaling**
- Designed for a single instance. Architecture supports scaling later (stateless jobs, shared database).

**6. Advanced Monitoring Dashboards**
- Basic logging and health checks are sufficient. Can integrate with monitoring tools later.

**7. Webhook Support**
- Would require authentication. Polling is simpler and meets current requirements.

**8. Historical Backfill**
- Assumes starting from current events. Historical backfill can be implemented as a separate tool if needed.

**9. Event Deduplication Beyond Database Constraints**
- Relies on database unique constraints. More sophisticated deduplication is not needed for current scale.

**10. Multi-environment Configuration Management**
- Basic environment variables are sufficient. Configuration validation and management can be added later.

## Design Principles

1. **Extensibility First**: Architecture supports future features without rewrites
2. **Fail Gracefully**: System continues operating despite individual failures
3. **Observable**: Clear logging enables debugging and monitoring
4. **Idempotent**: Safe to run multiple times, restart-friendly
5. **Pragmatic**: Simple solutions over complex ones, scalable when needed

This design prioritizes reliability, maintainability, and operational simplicity while providing a foundation for analytics capabilities.
