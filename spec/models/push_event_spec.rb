require 'rails_helper'

RSpec.describe PushEvent, type: :model do
  subject { build(:push_event) }
  
  describe 'validations' do
    it { is_expected.to validate_presence_of(:repository_id) }
    it { is_expected.to validate_presence_of(:push_id) }
    it { is_expected.to validate_uniqueness_of(:push_id).case_insensitive }
    it { is_expected.to validate_presence_of(:ref) }
    it { is_expected.to validate_presence_of(:head) }
    it { is_expected.to validate_inclusion_of(:enrichment_status).in_array(PushEvent::ENRICHMENT_STATUSES) }

    it 'allows empty string for before field' do
      push_event = build(:push_event, before: '')
      expect(push_event).to be_valid
    end

    it 'does not allow nil for before field' do
      push_event = build(:push_event)
      push_event.before = nil  # Set directly after build to override factory
      expect(push_event).not_to be_valid
    end
  end

  describe 'associations' do
    it { is_expected.to belong_to(:github_event) }
    it { is_expected.to belong_to(:actor).optional(true) }
    it { is_expected.to belong_to(:enriched_repository).class_name('Repository').optional(true) }
  end

  describe 'scopes' do
    let!(:enriched) { create(:push_event, :enriched) }
    let!(:pending) { create(:push_event, enrichment_status: 'pending') }
    let!(:failed) { create(:push_event, enrichment_status: 'failed') }
    let!(:in_progress) { create(:push_event, enrichment_status: 'in_progress') }

    describe '.enriched' do
      it 'filters enriched events' do
        expect(described_class.enriched).to include(enriched)
        expect(described_class.enriched).not_to include(pending)
        expect(described_class.enriched).not_to include(failed)
      end
    end

    describe '.pending_enrichment' do
      it 'filters pending events' do
        expect(described_class.pending_enrichment).to include(pending)
        expect(described_class.pending_enrichment).not_to include(enriched)
        expect(described_class.pending_enrichment).not_to include(failed)
      end
    end

    describe '.failed_enrichment' do
      it 'filters failed events' do
        expect(described_class.failed_enrichment).to include(failed)
        expect(described_class.failed_enrichment).not_to include(enriched)
        expect(described_class.failed_enrichment).not_to include(pending)
      end
    end

    describe '.by_repository' do
      it 'filters by repository_id' do
        repo_id = enriched.repository_id
        expect(described_class.by_repository(repo_id)).to include(enriched)
        expect(described_class.by_repository('different/repo')).not_to include(enriched)
      end
    end

    describe '.by_enrichment_status' do
      it 'filters by enrichment status' do
        expect(described_class.by_enrichment_status('pending')).to include(pending)
        expect(described_class.by_enrichment_status('pending')).not_to include(enriched)
      end
    end
  end

  describe '#enriched?' do
    it 'returns true when status is completed' do
      event = build(:push_event, enrichment_status: 'completed')
      expect(event.enriched?).to be true
    end

    it 'returns false when status is pending' do
      event = build(:push_event, enrichment_status: 'pending')
      expect(event.enriched?).to be false
    end

    it 'returns false when status is failed' do
      event = build(:push_event, enrichment_status: 'failed')
      expect(event.enriched?).to be false
    end
  end

  describe '#pending_enrichment?' do
    it 'returns true when status is pending' do
      event = build(:push_event, enrichment_status: 'pending')
      expect(event.pending_enrichment?).to be true
    end

    it 'returns false when status is completed' do
      event = build(:push_event, enrichment_status: 'completed')
      expect(event.pending_enrichment?).to be false
    end
  end

  describe 'status transitions' do
    let(:push_event) { create(:push_event) }

    describe '#mark_enrichment_in_progress!' do
      it 'transitions to in_progress' do
        push_event.mark_enrichment_in_progress!
        expect(push_event.reload.enrichment_status).to eq('in_progress')
      end
    end

    describe '#mark_enrichment_completed!' do
      it 'transitions to completed' do
        push_event.mark_enrichment_completed!
        expect(push_event.reload.enrichment_status).to eq('completed')
      end
    end

    describe '#mark_enrichment_failed!' do
      it 'transitions to failed' do
        push_event.mark_enrichment_failed!
        expect(push_event.reload.enrichment_status).to eq('failed')
      end
    end
  end

  describe 'ENRICHMENT_STATUSES constant' do
    it 'includes all valid statuses' do
      expect(PushEvent::ENRICHMENT_STATUSES).to contain_exactly(
        'pending',
        'in_progress',
        'completed',
        'failed'
      )
    end
  end
end
