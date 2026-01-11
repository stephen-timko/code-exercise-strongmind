require 'rails_helper'

RSpec.describe IngestGitHubEventsJob, type: :job do
  let(:events_endpoint) { 'https://api.github.com/events' }
  let(:sample_events) do
    [
      {
        'id' => '12345',
        'type' => 'PushEvent',
        'actor' => { 'login' => 'user1' },
        'repo' => {
          'id' => 123,
          'full_name' => 'owner/repo1',
          'name' => 'repo1'
        },
        'payload' => {
          'push_id' => 67890,
          'ref' => 'refs/heads/main',
          'head' => 'abc123',
          'before' => 'def456'
        }
      },
      {
        'id' => '12346',
        'type' => 'PullRequestEvent',
        'actor' => { 'login' => 'user2' },
        'repo' => { 'name' => 'owner/repo2' }
      },
      {
        'id' => '12347',
        'type' => 'PushEvent',
        'actor' => { 'login' => 'user3' },
        'repo' => {
          'id' => 124,
          'full_name' => 'owner/repo3',
          'name' => 'repo3'
        },
        'payload' => {
          'push_id' => 67891,
          'ref' => 'refs/heads/develop',
          'head' => 'xyz789',
          'before' => 'uvw012'
        }
      }
    ]
  end

  describe '#perform' do
    context 'with successful ingestion' do
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
      end

      it 'stores all events' do
        expect { described_class.new.perform }
          .to change(GitHubEvent, :count).by(3)
      end

      it 'only creates PushEvents for PushEvent type' do
        expect { described_class.new.perform }
          .to change(PushEvent, :count).by(2) # Only 2 PushEvents
      end

      it 'marks events as processed' do
        described_class.new.perform

        push_events = PushEvent.all
        expect(push_events.all? { |pe| pe.github_event.processed? }).to be true
      end

      it 'sets enrichment status to pending' do
        described_class.new.perform

        push_events = PushEvent.all
        expect(push_events.all? { |pe| pe.enrichment_status == 'pending' }).to be true
      end

      it 'stores raw event payloads' do
        described_class.new.perform

        github_event = GitHubEvent.find_by(event_id: '12345')
        expect(github_event.raw_payload['type']).to eq('PushEvent')
        expect(github_event.raw_payload['id']).to eq('12345')
      end

      it 'returns ETag for next request' do
        result = described_class.new.perform
        expect(result).to eq('"test-etag"')
      end
    end

    context 'with idempotency' do
      before do
        stub_request(:get, events_endpoint)
          .to_return(
            status: 200,
            body: sample_events.to_json,
            headers: {
              'X-RateLimit-Remaining' => '50',
              'X-RateLimit-Limit' => '60',
              'ETag' => '"test-etag"'
            }
          )
      end

      it 'does not create duplicate events on second run' do
        described_class.new.perform
        initial_count = GitHubEvent.count
        push_events_count = PushEvent.count

        described_class.new.perform

        expect(GitHubEvent.count).to eq(initial_count)
        expect(PushEvent.count).to eq(push_events_count)
      end
    end

    context 'with 304 Not Modified' do
      before do
        stub_request(:get, events_endpoint)
          .with(headers: { 'If-None-Match' => '"existing-etag"' })
          .to_return(status: 304)
      end

      it 'skips ingestion' do
        expect { described_class.new.perform(etag: '"existing-etag"') }
          .not_to change(GitHubEvent, :count)
      end

      it 'returns early' do
        result = described_class.new.perform(etag: '"existing-etag"')
        expect(result).to be_nil
      end
    end

    context 'with rate limit error' do
      before do
        stub_request(:get, events_endpoint)
          .to_return(
            status: 403,
            headers: {
              'X-RateLimit-Remaining' => '0',
              'X-RateLimit-Reset' => (Time.current + 1.hour).to_i.to_s
            }
          )
      end

      it 'raises RateLimitExceeded for retry' do
        expect { described_class.new.perform }
          .to raise_error(GitHubApiClient::RateLimitExceeded)
      end
    end

    context 'with malformed event data' do
      let(:malformed_events) do
        [
          { 'id' => '12345', 'type' => 'PushEvent' }, # Missing required fields
          { 'invalid' => 'data' } # Missing id
        ]
      end

      before do
        stub_request(:get, events_endpoint)
          .to_return(status: 200, body: malformed_events.to_json)
      end

      it 'handles gracefully without crashing' do
        expect { described_class.new.perform }.not_to raise_error
      end

      it 'stores events with missing fields' do
        described_class.new.perform

        event = GitHubEvent.find_by(event_id: '12345')
        expect(event).to be_present
      end

      it 'does not create PushEvent for invalid data' do
        expect { described_class.new.perform }
          .not_to change(PushEvent, :count)
      end

      it 'logs errors for malformed events' do
        expect(Rails.logger).to receive(:error).at_least(:once)
        described_class.new.perform
      end
    end

    context 'with empty events array' do
      before do
        stub_request(:get, events_endpoint)
          .to_return(
            status: 200,
            body: [].to_json,
            headers: {
              'X-RateLimit-Remaining' => '50',
              'X-RateLimit-Limit' => '60'
            }
          )
      end

      it 'handles empty response gracefully' do
        expect { described_class.new.perform }.not_to raise_error
        expect(GitHubEvent.count).to eq(0)
        expect(PushEvent.count).to eq(0)
      end
    end

    context 'with network error' do
      before do
        stub_request(:get, events_endpoint).to_timeout
      end

      it 'raises NetworkError for retry' do
        expect { described_class.new.perform }
          .to raise_error(GitHubApiClient::NetworkError)
      end
    end
  end
end
