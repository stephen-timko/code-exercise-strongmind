require 'rails_helper'

RSpec.describe GitHubEvent, type: :model do
  subject { build(:github_event) }
  
  describe 'validations' do
    it { is_expected.to validate_presence_of(:event_id) }
    it { is_expected.to validate_uniqueness_of(:event_id).case_insensitive }
    it { is_expected.to validate_presence_of(:event_type) }
    it { is_expected.to validate_presence_of(:ingested_at) }

    describe 'raw_payload_or_s3_key validation' do
      it 'valid when raw_payload is present' do
        event = build(:github_event, raw_payload: { 'id' => '123' }, s3_key: nil)
        expect(event).to be_valid
      end

      it 'valid when s3_key is present' do
        event = build(:github_event, raw_payload: nil, s3_key: 'events/2026/01/15/123.json')
        expect(event).to be_valid
      end

      it 'valid when both are present' do
        event = build(:github_event, raw_payload: { 'id' => '123' }, s3_key: 'events/2026/01/15/123.json')
        expect(event).to be_valid
      end

      it 'invalid when both are blank' do
        event = build(:github_event, raw_payload: nil, s3_key: nil)
        expect(event).not_to be_valid
        expect(event.errors[:base]).to include('Either raw_payload or s3_key must be present')
      end
    end
  end

  describe 'associations' do
    it { is_expected.to have_one(:push_event) }
  end

  describe 'scopes' do
    let!(:push_event) { create(:github_event, event_type: 'PushEvent') }
    let!(:pr_event) { create(:github_event, event_type: 'PullRequestEvent') }
    let!(:processed_event) { create(:github_event, :processed, event_type: 'PushEvent') }
    let!(:unprocessed_event) { create(:github_event, event_type: 'IssueEvent', processed_at: nil) }

    describe '.by_type' do
      it 'filters events by type' do
        expect(described_class.by_type('PushEvent')).to include(push_event)
        expect(described_class.by_type('PushEvent')).not_to include(pr_event)
      end
    end

    describe '.push_events' do
      it 'returns only PushEvent types' do
        expect(described_class.push_events).to include(push_event)
        expect(described_class.push_events).not_to include(pr_event)
      end
    end

    describe '.processed' do
      it 'returns only processed events' do
        expect(described_class.processed).to include(processed_event)
        expect(described_class.processed).not_to include(unprocessed_event)
      end
    end

    describe '.unprocessed' do
      it 'returns only unprocessed events' do
        expect(described_class.unprocessed).to include(unprocessed_event)
        expect(described_class.unprocessed).not_to include(processed_event)
      end
    end
  end

  describe '#push_event?' do
    it 'returns true for PushEvent type' do
      event = build(:github_event, event_type: 'PushEvent')
      expect(event.push_event?).to be true
    end

    it 'returns false for other types' do
      event = build(:github_event, event_type: 'PullRequestEvent')
      expect(event.push_event?).to be false
    end
  end

  describe '#processed?' do
    it 'returns true when processed_at is set' do
      event = build(:github_event, processed_at: Time.current)
      expect(event.processed?).to be true
    end

    it 'returns false when processed_at is nil' do
      event = build(:github_event, processed_at: nil)
      expect(event.processed?).to be false
    end
  end

  describe '#mark_as_processed!' do
    it 'sets processed_at timestamp' do
      event = create(:github_event, processed_at: nil)
      event.mark_as_processed!

      expect(event.reload.processed_at).to be_present
    end

    it 'updates existing processed_at' do
      old_time = 1.hour.ago
      event = create(:github_event, processed_at: old_time)
      
      event.mark_as_processed!
      
      expect(event.reload.processed_at).to be > old_time
    end
  end

  describe '#store_payload' do
    let(:payload) { { 'id' => '12345', 'type' => 'PushEvent' } }
    let(:event) { build(:github_event, raw_payload: nil, s3_key: nil) }

    context 'when S3 is disabled' do
      before do
        stub_const('ObjectStorage::Config::ENABLED', false)
        allow(ObjectStorageService).to receive(:store).and_return(nil)
      end

      it 'stores payload in JSONB column' do
        event.store_payload(payload)

        expect(event.read_attribute(:raw_payload)).to eq(payload)
        expect(event.s3_key).to be_nil
      end
    end

    context 'when S3 is enabled' do
      let(:s3_key) { 'events/2026/01/15/12345.json' }

      before do
        stub_const('ObjectStorage::Config::ENABLED', true)
        allow(ObjectStorageService).to receive(:store).with(event.event_id, payload).and_return(s3_key)
      end

      it 'stores payload in S3 and sets s3_key' do
        event.store_payload(payload)

        expect(event.s3_key).to eq(s3_key)
        expect(event.read_attribute(:raw_payload)).to be_nil
        expect(ObjectStorageService).to have_received(:store).with(event.event_id, payload)
      end
    end
  end

  describe '#raw_payload' do
    let(:payload) { { 'id' => '12345', 'type' => 'PushEvent' } }

    context 'when stored in JSONB' do
      it 'returns payload from database' do
        event = create(:github_event, raw_payload: payload, s3_key: nil)
        expect(event.raw_payload).to eq(payload)
      end
    end

    context 'when stored in S3' do
      let(:s3_key) { 'events/2026/01/15/12345.json' }

      before do
        allow(ObjectStorageService).to receive(:retrieve).and_return(payload)
      end

      it 'retrieves payload from S3' do
        event = create(:github_event, raw_payload: nil, s3_key: s3_key)
        result = event.raw_payload
        expect(result).to eq(payload)
        expect(ObjectStorageService).to have_received(:retrieve).with(s3_key)
      end

      it 'caches retrieved payload' do
        event = create(:github_event, raw_payload: nil, s3_key: s3_key)
        event.raw_payload # First call
        event.raw_payload # Second call
        
        expect(ObjectStorageService).to have_received(:retrieve).with(s3_key).once
      end

      context 'when S3 retrieval fails' do
        let(:fallback_payload) { { 'id' => '99999', 'type' => 'PullRequestEvent' } }

        before do
          allow(ObjectStorageService).to receive(:retrieve).and_raise(ObjectStorageService::StorageError, 'S3 error')
          allow(Rails.logger).to receive(:error)
        end

        it 'falls back to JSONB column' do
          event = create(:github_event, raw_payload: fallback_payload, s3_key: s3_key)
          expect(event.raw_payload).to eq(fallback_payload)
        end

        it 'logs the error' do
          event = create(:github_event, raw_payload: fallback_payload, s3_key: s3_key)
          event.raw_payload
          expect(Rails.logger).to have_received(:error).with(/Failed to retrieve payload from S3/)
        end
      end
    end
  end
end
