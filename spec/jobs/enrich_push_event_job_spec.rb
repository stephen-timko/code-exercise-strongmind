require 'rails_helper'

RSpec.describe EnrichPushEventJob, type: :job do
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

  describe '#perform' do
    context 'with successful enrichment' do
      before do
        stub_request(:get, actor_url)
          .to_return(status: 200, body: actor_data.to_json)

        stub_request(:get, repo_url)
          .to_return(status: 200, body: repo_data.to_json)
      end

      it 'enriches the push event' do
        described_class.new.perform(push_event.id)

        push_event.reload
        expect(push_event.enrichment_status).to eq('completed')
        expect(push_event.actor).to be_present
        expect(push_event.enriched_repository).to be_present
      end

      it 'creates actor and repository records' do
        expect { described_class.new.perform(push_event.id) }
          .to change(Actor, :count).by(1)
          .and change(Repository, :count).by(1)
      end

      it 'links actor to push event' do
        described_class.new.perform(push_event.id)

        push_event.reload
        expect(push_event.actor.login).to eq('testuser')
      end

      it 'links repository to push event' do
        described_class.new.perform(push_event.id)

        push_event.reload
        expect(push_event.enriched_repository.full_name).to eq('owner/repo')
      end
    end

    context 'with already enriched event' do
      let(:push_event) { create(:push_event, :enriched, github_event: github_event) }

      it 'skips enrichment' do
        expect(EnrichmentService).not_to receive(:enrich)
        described_class.new.perform(push_event.id)
      end

      it 'does not refetch data' do
        expect(WebMock).not_to have_requested(:get, /api\.github\.com/)
        described_class.new.perform(push_event.id)
      end
    end

    context 'with enrichment in progress' do
      before do
        push_event.update!(enrichment_status: 'in_progress')
      end

      it 'skips enrichment' do
        expect(EnrichmentService).not_to receive(:enrich)
        described_class.new.perform(push_event.id)
      end
    end

    context 'with non-existent push event' do
      it 'raises RecordNotFound' do
        expect { described_class.new.perform(99999) }
          .to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    context 'with enrichment failure' do
      before do
        stub_request(:get, actor_url).to_return(status: 404)
        stub_request(:get, repo_url).to_return(status: 404)
      end

      it 'marks event as failed' do
        begin
          described_class.new.perform(push_event.id)
        rescue EnrichmentService::EnrichmentError
          # Expected - job raises error on failure
        end

        push_event.reload
        expect(push_event.enrichment_status).to eq('failed')
      end

      it 'raises EnrichmentError for retry' do
        expect { described_class.new.perform(push_event.id) }
          .to raise_error(EnrichmentService::EnrichmentError)
      end
    end

    context 'with network error' do
      before do
        stub_request(:get, actor_url).to_timeout
        stub_request(:get, repo_url).to_timeout
      end

      it 'raises EnrichmentError for retry' do
        expect { described_class.new.perform(push_event.id) }
          .to raise_error(EnrichmentService::EnrichmentError)
      end
    end

    context 'with rate limit error' do
      before do
        stub_request(:get, actor_url)
          .to_return(
            status: 403,
            headers: {
              'X-RateLimit-Remaining' => '0',
              'X-RateLimit-Reset' => (Time.current + 1.hour).to_i.to_s
            }
          )
      end

      it 'raises EnrichmentError for retry' do
        expect { described_class.new.perform(push_event.id) }
          .to raise_error(EnrichmentService::EnrichmentError)
      end
    end
  end
end
