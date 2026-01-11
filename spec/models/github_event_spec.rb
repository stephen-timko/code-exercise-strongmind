require 'rails_helper'

RSpec.describe GitHubEvent, type: :model do
  describe 'validations' do
    it { is_expected.to validate_presence_of(:event_id) }
    it { is_expected.to validate_uniqueness_of(:event_id) }
    it { is_expected.to validate_presence_of(:event_type) }
    it { is_expected.to validate_presence_of(:raw_payload) }
    it { is_expected.to validate_presence_of(:ingested_at) }
  end

  describe 'associations' do
    it { is_expected.to have_one(:push_event).dependent(:destroy) }
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
end
