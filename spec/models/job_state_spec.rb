require 'rails_helper'

RSpec.describe JobState, type: :model do
  describe 'validations' do
    it { is_expected.to validate_presence_of(:key) }
    it { is_expected.to validate_uniqueness_of(:key) }
  end

  describe '.get' do
    context 'when key exists' do
      let!(:job_state) { create(:job_state, key: 'test_key', value: 'test_value') }

      it 'returns the value' do
        expect(described_class.get('test_key')).to eq('test_value')
      end
    end

    context 'when key does not exist' do
      it 'returns nil' do
        expect(described_class.get('nonexistent_key')).to be_nil
      end
    end
  end

  describe '.set' do
    context 'when key does not exist' do
      it 'creates a new job state' do
        expect { described_class.set('new_key', 'new_value') }
          .to change(described_class, :count).by(1)
      end

      it 'returns the value' do
        expect(described_class.set('new_key', 'new_value')).to eq('new_value')
      end

      it 'sets the key and value' do
        described_class.set('new_key', 'new_value')
        state = described_class.find_by(key: 'new_key')
        expect(state.value).to eq('new_value')
      end
    end

    context 'when key already exists' do
      let!(:existing_state) { create(:job_state, key: 'existing_key', value: 'old_value') }

      it 'updates the existing job state' do
        expect { described_class.set('existing_key', 'new_value') }
          .not_to change(described_class, :count)
      end

      it 'updates the value' do
        described_class.set('existing_key', 'new_value')
        expect(existing_state.reload.value).to eq('new_value')
      end

      it 'returns the new value' do
        expect(described_class.set('existing_key', 'new_value')).to eq('new_value')
      end
    end

    context 'with nil value' do
      it 'allows nil value' do
        expect { described_class.set('key_with_nil', nil) }
          .to change(described_class, :count).by(1)
        
        expect(described_class.get('key_with_nil')).to be_nil
      end
    end
  end

  describe 'ETag persistence usage' do
    it 'can store and retrieve ETag values' do
      etag = '"test-etag-123"'
      described_class.set('github_events_etag', etag)
      
      retrieved_etag = described_class.get('github_events_etag')
      expect(retrieved_etag).to eq(etag)
    end

    it 'can update ETag values' do
      described_class.set('github_events_etag', '"old-etag"')
      described_class.set('github_events_etag', '"new-etag"')
      
      expect(described_class.get('github_events_etag')).to eq('"new-etag"')
    end
  end
end
