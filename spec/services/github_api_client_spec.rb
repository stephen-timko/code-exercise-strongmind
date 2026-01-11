require 'rails_helper'

RSpec.describe GitHubApiClient do
  let(:client) { described_class.new }
  let(:base_url) { 'https://api.github.com' }
  let(:events_endpoint) { "#{base_url}/events" }

  describe '#fetch_events' do
    let(:sample_events) do
      [
        {
          'id' => '12345',
          'type' => 'PushEvent',
          'actor' => { 'login' => 'testuser' },
          'repo' => { 'name' => 'test/repo' }
        }
      ]
    end

    context 'with successful response' do
      before do
        stub_request(:get, events_endpoint)
          .to_return(
            status: 200,
            body: sample_events.to_json,
            headers: {
              'X-RateLimit-Remaining' => '50',
              'X-RateLimit-Limit' => '60',
              'X-RateLimit-Reset' => (Time.current + 1.hour).to_i.to_s,
              'ETag' => '"abc123"'
            }
          )
      end

      it 'fetches events successfully' do
        result = client.fetch_events

        expect(result[:data]).to eq(sample_events)
        expect(result[:not_modified]).to be false
        expect(result[:etag]).to eq('"abc123"')
      end

      it 'tracks rate limit information' do
        result = client.fetch_events

        expect(result[:rate_limit_info][:remaining]).to eq(50)
        expect(result[:rate_limit_info][:limit]).to eq(60)
        expect(client.rate_limit_remaining).to eq(50)
      end

      it 'sets rate limit reset time' do
        client.fetch_events

        expect(client.rate_limit_reset_at).to be_present
      end
    end

    context 'with 304 Not Modified' do
      before do
        stub_request(:get, events_endpoint)
          .with(headers: { 'If-None-Match' => '"abc123"' })
          .to_return(
            status: 304,
            headers: {
              'X-RateLimit-Remaining' => '50',
              'X-RateLimit-Reset' => (Time.current + 1.hour).to_i.to_s
            }
          )
      end

      it 'handles not modified response' do
        result = client.fetch_events(etag: '"abc123"')

        expect(result[:not_modified]).to be true
        expect(result[:data]).to eq([])
        expect(result[:etag]).to eq('"abc123"')
      end
    end

    context 'with rate limit exceeded (403)' do
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

      it 'raises RateLimitExceeded error' do
        expect { client.fetch_events }.to raise_error(GitHubApiClient::RateLimitExceeded)
      end
    end

    context 'with rate limit exceeded (429)' do
      before do
        stub_request(:get, events_endpoint)
          .to_return(
            status: 429,
            headers: {
              'X-RateLimit-Remaining' => '0',
              'X-RateLimit-Reset' => (Time.current + 1.hour).to_i.to_s
            }
          )
      end

      it 'raises RateLimitExceeded error' do
        expect { client.fetch_events }.to raise_error(GitHubApiClient::RateLimitExceeded)
      end
    end

    context 'with network error' do
      before do
        stub_request(:get, events_endpoint).to_timeout
      end

      it 'raises NetworkError' do
        expect { client.fetch_events }.to raise_error(GitHubApiClient::NetworkError)
      end
    end

    context 'with API error (404)' do
      before do
        stub_request(:get, events_endpoint)
          .to_return(status: 404)
      end

      it 'raises ApiError' do
        expect { client.fetch_events }.to raise_error(GitHubApiClient::ApiError)
      end
    end
  end

  describe '#fetch_resource' do
    let(:resource_url) { "#{base_url}/users/testuser" }
    let(:user_data) { { 'id' => 123, 'login' => 'testuser' } }

    context 'with successful response' do
      before do
        stub_request(:get, resource_url)
          .to_return(
            status: 200,
            body: user_data.to_json,
            headers: {
              'X-RateLimit-Remaining' => '50',
              'ETag' => '"def456"'
            }
          )
      end

      it 'fetches resource successfully' do
        result = client.fetch_resource(resource_url)

        expect(result[:data]).to eq(user_data)
        expect(result[:not_modified]).to be false
        expect(result[:etag]).to eq('"def456"')
      end
    end

    context 'with 304 Not Modified' do
      before do
        stub_request(:get, resource_url)
          .with(headers: { 'If-None-Match' => '"def456"' })
          .to_return(status: 304)
      end

      it 'returns not_modified response' do
        result = client.fetch_resource(resource_url, etag: '"def456"')

        expect(result[:not_modified]).to be true
        expect(result[:data]).to be_nil
      end
    end
  end

  describe '#rate_limit_exhausted?' do
    it 'returns true when rate limit is 0' do
      client.instance_variable_set(:@rate_limit_remaining, 0)
      expect(client.rate_limit_exhausted?).to be true
    end

    it 'returns false when rate limit remains' do
      client.instance_variable_set(:@rate_limit_remaining, 10)
      expect(client.rate_limit_exhausted?).to be false
    end

    it 'returns false when rate limit is nil' do
      client.instance_variable_set(:@rate_limit_remaining, nil)
      expect(client.rate_limit_exhausted?).to be false
    end
  end

  describe '#rate_limit_low?' do
    it 'returns true when remaining is below threshold' do
      client.instance_variable_set(:@rate_limit_remaining, 5)
      expect(client.rate_limit_low?(threshold: 10)).to be true
    end

    it 'returns false when remaining is above threshold' do
      client.instance_variable_set(:@rate_limit_remaining, 20)
      expect(client.rate_limit_low?(threshold: 10)).to be false
    end
  end

  describe '#seconds_until_reset' do
    it 'returns seconds until reset' do
      reset_time = Time.current + 3600
      client.instance_variable_set(:@rate_limit_reset_at, reset_time)
      
      seconds = client.seconds_until_reset
      expect(seconds).to be_within(10).of(3600)
    end

    it 'returns 0 when reset time is in the past' do
      reset_time = Time.current - 100
      client.instance_variable_set(:@rate_limit_reset_at, reset_time)
      
      expect(client.seconds_until_reset).to eq(0)
    end

    it 'returns nil when reset_at is nil' do
      client.instance_variable_set(:@rate_limit_reset_at, nil)
      expect(client.seconds_until_reset).to be_nil
    end
  end
end
