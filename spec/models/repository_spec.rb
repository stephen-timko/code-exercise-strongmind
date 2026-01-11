require 'rails_helper'

RSpec.describe Repository, type: :model do
  subject { build(:repository) }
  
  describe 'validations' do
    it { is_expected.to validate_presence_of(:github_id) }
    it { is_expected.to validate_uniqueness_of(:github_id).case_insensitive }
    it { is_expected.to validate_presence_of(:full_name) }
    it { is_expected.to validate_presence_of(:raw_data) }
    it { is_expected.to validate_presence_of(:fetched_at) }
  end

  describe 'associations' do
    it { is_expected.to have_many(:push_events).with_foreign_key('enriched_repository_id') }
  end

  describe 'scopes' do
    let!(:repo1) { create(:repository, github_id: '123', full_name: 'owner/repo1') }
    let!(:repo2) { create(:repository, github_id: '456', full_name: 'owner/repo2') }

    describe '.by_github_id' do
      it 'filters repositories by github_id' do
        expect(described_class.by_github_id('123')).to include(repo1)
        expect(described_class.by_github_id('123')).not_to include(repo2)
      end
    end

    describe '.by_full_name' do
      it 'filters repositories by full_name' do
        expect(described_class.by_full_name('owner/repo1')).to include(repo1)
        expect(described_class.by_full_name('owner/repo1')).not_to include(repo2)
      end
    end
  end

  describe '#cache_fresh?' do
    it 'returns true when fetched_at is within TTL' do
      repo = create(:repository, fetched_at: 1.hour.ago)
      expect(repo.cache_fresh?(ttl: 24.hours)).to be true
    end

    it 'returns false when fetched_at is beyond TTL' do
      repo = create(:repository, fetched_at: 25.hours.ago)
      expect(repo.cache_fresh?(ttl: 24.hours)).to be false
    end

    it 'returns false when fetched_at is nil' do
      repo = build(:repository, fetched_at: nil)
      expect(repo.cache_fresh?).to be false
    end

    it 'uses custom TTL when provided' do
      repo = create(:repository, fetched_at: 2.hours.ago)
      expect(repo.cache_fresh?(ttl: 1.hour)).to be false
      expect(repo.cache_fresh?(ttl: 3.hours)).to be true
    end
  end

  describe '#cache_stale?' do
    it 'returns true when cache is stale' do
      repo = create(:repository, fetched_at: 25.hours.ago)
      expect(repo.cache_stale?(ttl: 24.hours)).to be true
    end

    it 'returns false when cache is fresh' do
      repo = create(:repository, fetched_at: 1.hour.ago)
      expect(repo.cache_stale?(ttl: 24.hours)).to be false
    end

    it 'is the inverse of cache_fresh?' do
      repo = create(:repository, fetched_at: 1.hour.ago)
      expect(repo.cache_stale?).to eq(!repo.cache_fresh?)
    end
  end
end
