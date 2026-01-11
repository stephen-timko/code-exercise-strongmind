require 'rails_helper'

RSpec.describe 'GitHub Events Ingestion End-to-End', type: :integration do
  let(:events_endpoint) { 'https://api.github.com/events' }

  let(:sample_events) do
    [
      {
        'id' => '12345',
        'type' => 'PushEvent',
        'actor' => {
          'id' => 123,
          'login' => 'testuser',
          'url' => 'https://api.github.com/users/testuser'
        },
        'repo' => {
          'id' => 456,
          'full_name' => 'owner/repo',
          'url' => 'https://api.github.com/repos/owner/repo'
        },
        'payload' => {
          'push_id' => 67890,
          'ref' => 'refs/heads/main',
          'head' => 'abc123',
          'before' => 'def456'
        }
      }
    ]
  end

  let(:actor_data) do
    {
      'id' => 123,
      'login' => 'testuser',
      'avatar_url' => 'https://avatars.githubusercontent.com/u/123'
    }
  end

  let(:repo_data) do
    {
      'id' => 456,
      'full_name' => 'owner/repo',
      'description' => 'Test repository'
    }
  end

  before do
    stub_request(:get, events_endpoint)
      .to_return(
        status: 200,
        body: sample_events.to_json,
        headers: {
          'X-RateLimit-Remaining' => '50',
          'X-RateLimit-Limit' => '60',
          'X-RateLimit-Reset' => (Time.current + 1.hour).to_i.to_s,
          'ETag' => '"test-etag"'
        }
      )

    stub_request(:get, 'https://api.github.com/users/testuser')
      .to_return(status: 200, body: actor_data.to_json)

    stub_request(:get, 'https://api.github.com/repos/owner/repo')
      .to_return(status: 200, body: repo_data.to_json)
  end

  it 'completes full ingestion and enrichment flow' do
    # Step 1: Ingest events
    IngestGitHubEventsJob.new.perform

    expect(GitHubEvent.count).to eq(1)
    expect(PushEvent.count).to eq(1)

    push_event = PushEvent.first
    expect(push_event.enrichment_status).to eq('pending')
    expect(push_event.github_event.processed?).to be true

    # Step 2: Enrich push event
    EnrichmentService.enrich(push_event)

    push_event.reload
    expect(push_event.enrichment_status).to eq('completed')
    expect(push_event.actor).to be_present
    expect(push_event.actor.login).to eq('testuser')
    expect(push_event.enriched_repository).to be_present
    expect(push_event.enriched_repository.full_name).to eq('owner/repo')
  end

  it 'stores raw event data for audit' do
    IngestGitHubEventsJob.new.perform

    github_event = GitHubEvent.first
    expect(github_event.raw_payload['type']).to eq('PushEvent')
    expect(github_event.raw_payload['id']).to eq('12345')
  end

  it 'creates structured push event data' do
    IngestGitHubEventsJob.new.perform

    push_event = PushEvent.first
    expect(push_event.repository_id).to eq('owner/repo')
    expect(push_event.push_id).to eq('67890')
    expect(push_event.ref).to eq('refs/heads/main')
    expect(push_event.head).to eq('abc123')
    expect(push_event.before).to eq('def456')
  end

  it 'is idempotent for ingestion' do
    IngestGitHubEventsJob.new.perform
    initial_count = GitHubEvent.count

    IngestGitHubEventsJob.new.perform

    expect(GitHubEvent.count).to eq(initial_count)
    expect(PushEvent.count).to eq(1)
  end

  it 'handles enrichment caching' do
    # First enrichment
    IngestGitHubEventsJob.new.perform
    push_event = PushEvent.first
    EnrichmentService.enrich(push_event)

    expect(Actor.count).to eq(1)
    expect(Repository.count).to eq(1)

    # Second enrichment (should use cache)
    another_push_event = create(:push_event, github_event: push_event.github_event)
    another_push_event.github_event.update!(
      raw_payload: push_event.github_event.raw_payload
    )

    # Clear previous requests to test caching
    WebMock.reset!
    
    # Stub requests in case they're needed (they shouldn't be due to caching)
    stub_request(:get, /api\.github\.com/).to_return(status: 200, body: {}.to_json)

    EnrichmentService.enrich(another_push_event)

    # Should reuse existing actor and repository
    expect(Actor.count).to eq(1)
    expect(Repository.count).to eq(1)
  end
end
