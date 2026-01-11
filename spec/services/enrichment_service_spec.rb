require 'rails_helper'

RSpec.describe EnrichmentService do
  let(:github_event) { create(:github_event, :processed) }
  let(:push_event) { create(:push_event, github_event: github_event) }
  let(:actor_url) { 'https://api.github.com/users/testuser' }
  let(:repo_url) { 'https://api.github.com/repos/owner/repo' }

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
    github_event.update!(
      raw_payload: github_event.raw_payload.merge(
        'actor' => { 'url' => actor_url, 'id' => 123 },
        'repo' => { 'url' => repo_url, 'id' => 456 }
      )
    )
  end

  describe '.enrich' do
    context 'with successful enrichment' do
      before do
        stub_request(:get, actor_url)
          .to_return(status: 200, body: actor_data.to_json)

        stub_request(:get, repo_url)
          .to_return(status: 200, body: repo_data.to_json)
      end

      it 'enriches actor and repository' do
        result = described_class.enrich(push_event)

        expect(result[:actor_enriched]).to be true
        expect(result[:repository_enriched]).to be true
        expect(result[:status]).to eq(:completed)
      end

      it 'creates actor record' do
        expect { described_class.enrich(push_event) }
          .to change(Actor, :count).by(1)

        actor = Actor.last
        expect(actor.github_id).to eq('123')
        expect(actor.login).to eq('testuser')
      end

      it 'creates repository record' do
        expect { described_class.enrich(push_event) }
          .to change(Repository, :count).by(1)

        repo = Repository.last
        expect(repo.github_id).to eq('456')
        expect(repo.full_name).to eq('owner/repo')
      end

      it 'updates push event status' do
        described_class.enrich(push_event)

        push_event.reload
        expect(push_event.enrichment_status).to eq('completed')
        expect(push_event.actor).to be_present
        expect(push_event.enriched_repository).to be_present
      end

      it 'marks enrichment as in_progress initially' do
        expect(push_event).to receive(:mark_enrichment_in_progress!)
        described_class.enrich(push_event)
      end
    end

    context 'with cached actor and repository' do
      let!(:actor) { create(:actor, github_id: '123', fetched_at: 1.hour.ago) }
      let!(:repository) { create(:repository, github_id: '456', fetched_at: 1.hour.ago) }

      it 'uses cached data without fetching' do
        expect(WebMock).not_to have_requested(:get, /api\.github\.com/)

        result = described_class.enrich(push_event)

        expect(result[:actor_enriched]).to be true
        expect(result[:repository_enriched]).to be true
        expect(result[:status]).to eq(:completed)
      end

      it 'links cached actor to push event' do
        described_class.enrich(push_event)

        expect(push_event.reload.actor).to eq(actor)
      end

      it 'links cached repository to push event' do
        described_class.enrich(push_event)

        expect(push_event.reload.enriched_repository).to eq(repository)
      end
    end

    context 'with stale cache' do
      let!(:actor) { create(:actor, github_id: '123', fetched_at: 25.hours.ago) }

      before do
        stub_request(:get, actor_url)
          .to_return(status: 200, body: actor_data.to_json)
        stub_request(:get, repo_url)
          .to_return(status: 200, body: repo_data.to_json)
      end

      it 'refetches stale data' do
        described_class.enrich(push_event)

        expect(WebMock).to have_requested(:get, actor_url).once
      end

      it 'updates cached data' do
        old_fetched_at = actor.fetched_at
        described_class.enrich(push_event)

        actor.reload
        expect(actor.fetched_at).to be > old_fetched_at
      end
    end

    context 'with partial enrichment failure' do
      before do
        stub_request(:get, actor_url)
          .to_return(status: 200, body: actor_data.to_json)

        stub_request(:get, repo_url)
          .to_return(status: 404)
      end

      it 'marks as completed with partial data' do
        result = described_class.enrich(push_event)

        expect(result[:actor_enriched]).to be true
        expect(result[:repository_enriched]).to be false
        expect(result[:status]).to eq(:partial)
        expect(push_event.reload.enrichment_status).to eq('completed')
      end

      it 'links successful actor' do
        described_class.enrich(push_event)

        expect(push_event.reload.actor).to be_present
        expect(push_event.enriched_repository).to be_nil
      end
    end

    context 'with complete enrichment failure' do
      before do
        stub_request(:get, actor_url).to_return(status: 404)
        stub_request(:get, repo_url).to_return(status: 404)
      end

      it 'marks as failed' do
        result = described_class.enrich(push_event)

        expect(result[:actor_enriched]).to be false
        expect(result[:repository_enriched]).to be false
        expect(result[:status]).to eq(:failed)
        expect(push_event.reload.enrichment_status).to eq('failed')
      end
    end

    context 'with missing actor URL' do
      before do
        github_event.update!(
          raw_payload: github_event.raw_payload.merge(
            'actor' => {},
            'repo' => { 'url' => repo_url, 'id' => 456 }
          )
        )
        stub_request(:get, repo_url)
          .to_return(status: 200, body: repo_data.to_json)
      end

      it 'skips actor enrichment' do
        result = described_class.enrich(push_event)

        expect(result[:actor_enriched]).to be false
        expect(result[:repository_enriched]).to be true
      end
    end

    context 'with network error' do
      before do
        stub_request(:get, actor_url).to_timeout
        stub_request(:get, repo_url).to_timeout
      end

      it 'marks as failed' do
        result = described_class.enrich(push_event)

        expect(result[:status]).to eq(:failed)
        expect(push_event.reload.enrichment_status).to eq('failed')
      end
    end

    context 'with exception during enrichment' do
      before do
        allow(push_event).to receive(:mark_enrichment_in_progress!).and_raise(StandardError, 'Database error')
      end

      it 'raises EnrichmentError' do
        expect { described_class.enrich(push_event) }
          .to raise_error(EnrichmentService::EnrichmentError)
      end

      it 'marks as failed on error' do
        begin
          described_class.enrich(push_event)
        rescue EnrichmentService::EnrichmentError
          # Expected
        end

        expect(push_event.reload.enrichment_status).to eq('failed')
      end
    end

    context 'with actor URL from login fallback' do
      before do
        github_event.update!(
          raw_payload: github_event.raw_payload.merge(
            'actor' => { 'login' => 'testuser', 'id' => 123 },
            'repo' => { 'url' => repo_url, 'id' => 456 }
          )
        )

        stub_request(:get, 'https://api.github.com/users/testuser')
          .to_return(status: 200, body: actor_data.to_json)

        stub_request(:get, repo_url)
          .to_return(status: 200, body: repo_data.to_json)
      end

      it 'constructs URL from login' do
        described_class.enrich(push_event)

        expect(WebMock).to have_requested(:get, 'https://api.github.com/users/testuser')
      end
    end
  end
end
