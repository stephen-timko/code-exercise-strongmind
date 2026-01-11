require 'rails_helper'

RSpec.describe Actor, type: :model do
  subject { build(:actor) }
  
  describe 'validations' do
    it { is_expected.to validate_presence_of(:github_id) }
    it { is_expected.to validate_uniqueness_of(:github_id).case_insensitive }
    it { is_expected.to validate_presence_of(:login) }
    it { is_expected.to validate_presence_of(:raw_data) }
    it { is_expected.to validate_presence_of(:fetched_at) }
  end

  describe 'associations' do
    it { is_expected.to have_many(:push_events) }
  end

  describe 'scopes' do
    let!(:actor1) { create(:actor, github_id: '123', login: 'user1') }
    let!(:actor2) { create(:actor, github_id: '456', login: 'user2') }

    describe '.by_github_id' do
      it 'filters actors by github_id' do
        expect(described_class.by_github_id('123')).to include(actor1)
        expect(described_class.by_github_id('123')).not_to include(actor2)
      end
    end

    describe '.by_login' do
      it 'filters actors by login' do
        expect(described_class.by_login('user1')).to include(actor1)
        expect(described_class.by_login('user1')).not_to include(actor2)
      end
    end
  end

  describe '#cache_fresh?' do
    it 'returns true when fetched_at is within TTL' do
      actor = create(:actor, fetched_at: 1.hour.ago)
      expect(actor.cache_fresh?(ttl: 24.hours)).to be true
    end

    it 'returns false when fetched_at is beyond TTL' do
      actor = create(:actor, fetched_at: 25.hours.ago)
      expect(actor.cache_fresh?(ttl: 24.hours)).to be false
    end

    it 'returns false when fetched_at is nil' do
      actor = build(:actor, fetched_at: nil)
      expect(actor.cache_fresh?).to be false
    end

    it 'uses custom TTL when provided' do
      actor = create(:actor, fetched_at: 2.hours.ago)
      expect(actor.cache_fresh?(ttl: 1.hour)).to be false
      expect(actor.cache_fresh?(ttl: 3.hours)).to be true
    end
  end

  describe '#cache_stale?' do
    it 'returns true when cache is stale' do
      actor = create(:actor, fetched_at: 25.hours.ago)
      expect(actor.cache_stale?(ttl: 24.hours)).to be true
    end

    it 'returns false when cache is fresh' do
      actor = create(:actor, fetched_at: 1.hour.ago)
      expect(actor.cache_stale?(ttl: 24.hours)).to be false
    end

    it 'is the inverse of cache_fresh?' do
      actor = create(:actor, fetched_at: 1.hour.ago)
      expect(actor.cache_stale?).to eq(!actor.cache_fresh?)
    end
  end
end
