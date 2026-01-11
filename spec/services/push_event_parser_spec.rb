require 'rails_helper'

RSpec.describe PushEventParser do
  describe '.parse' do
    let(:valid_payload) do
      {
        'type' => 'PushEvent',
        'id' => '12345',
        'repo' => {
          'id' => 123,
          'full_name' => 'owner/repo',
          'name' => 'repo'
        },
        'payload' => {
          'push_id' => 67890,
          'ref' => 'refs/heads/main',
          'head' => 'abc123def456',
          'before' => 'def456abc123'
        }
      }
    end

    context 'with valid PushEvent payload' do
      it 'parses all required fields' do
        result = described_class.parse(valid_payload)

        expect(result[:repository_id]).to eq('owner/repo')
        expect(result[:push_id]).to eq('67890')
        expect(result[:ref]).to eq('refs/heads/main')
        expect(result[:head]).to eq('abc123def456')
        expect(result[:before]).to eq('def456abc123')
      end
    end

    context 'with missing push_id' do
      let(:payload_without_push_id) do
        valid_payload.tap do |p|
          p['payload'].delete('push_id')
        end
      end

      it 'falls back to event id' do
        result = described_class.parse(payload_without_push_id)

        expect(result[:push_id]).to eq('12345')
      end
    end

    context 'with missing repository full_name and name' do
      let(:payload_without_full_name) do
        valid_payload.tap do |p|
          p['repo'].delete('full_name')
          p['repo'].delete('name')
          p['repo']['id'] = 456
        end
      end

      it 'falls back to repository id' do
        result = described_class.parse(payload_without_full_name)

        expect(result[:repository_id]).to eq('456')
      end
    end

    context 'with repository name instead of full_name' do
      let(:payload_with_name) do
        valid_payload.tap do |p|
          p['repo'].delete('full_name')
          p['repo']['name'] = 'owner/repo'
        end
      end

      it 'uses name field' do
        result = described_class.parse(payload_with_name)

        expect(result[:repository_id]).to eq('owner/repo')
      end
    end

    context 'with empty before (initial commit)' do
      let(:initial_commit_payload) do
        valid_payload.tap do |p|
          p['payload']['before'] = ''
        end
      end

      it 'allows empty string for before' do
        result = described_class.parse(initial_commit_payload)

        expect(result[:before]).to eq('')
      end
    end

    context 'with missing before field' do
      let(:payload_without_before) do
        valid_payload.tap do |p|
          p['payload'].delete('before')
        end
      end

      it 'defaults to empty string' do
        result = described_class.parse(payload_without_before)

        expect(result[:before]).to eq('')
      end
    end

    context 'with head from commits array' do
      let(:payload_with_commits) do
        valid_payload.tap do |p|
          p['payload'].delete('head')
          p['payload']['commits'] = [
            { 'sha' => 'commit1' },
            { 'sha' => 'commit2' }
          ]
        end
      end

      it 'extracts head from last commit' do
        result = described_class.parse(payload_with_commits)

        expect(result[:head]).to eq('commit2')
      end
    end

    context 'with head from head_commit' do
      let(:payload_with_head_commit) do
        valid_payload.tap do |p|
          p['payload'].delete('head')
          p['payload']['head_commit'] = { 'sha' => 'headsha123' }
        end
      end

      it 'extracts head from head_commit' do
        result = described_class.parse(payload_with_head_commit)

        expect(result[:head]).to eq('headsha123')
      end
    end

    context 'with non-PushEvent type' do
      let(:non_push_event) do
        valid_payload.tap { |p| p['type'] = 'PullRequestEvent' }
      end

      it 'raises ParseError' do
        expect { described_class.parse(non_push_event) }
          .to raise_error(PushEventParser::ParseError, /not PushEvent/)
      end
    end

    context 'with missing required fields' do
      let(:incomplete_payload) do
        { 'type' => 'PushEvent' }
      end

      it 'raises ParseError with missing fields' do
        expect { described_class.parse(incomplete_payload) }
          .to raise_error(PushEventParser::ParseError, /Missing required fields/)
      end
    end

    context 'with missing repository_id' do
      let(:payload_without_repo) do
        valid_payload.tap { |p| p.delete('repo') }
      end

      it 'raises ParseError' do
        expect { described_class.parse(payload_without_repo) }
          .to raise_error(PushEventParser::ParseError, /repository_id/)
      end
    end

    context 'with missing ref' do
      let(:payload_without_ref) do
        valid_payload.tap { |p| p['payload'].delete('ref') }
      end

      it 'raises ParseError' do
        expect { described_class.parse(payload_without_ref) }
          .to raise_error(PushEventParser::ParseError, /ref/)
      end
    end

    context 'with missing head' do
      let(:payload_without_head) do
        valid_payload.tap do |p|
          p['payload'].delete('head')
          p['payload'].delete('commits')
          p['payload'].delete('head_commit')
        end
      end

      it 'defaults to empty string and raises ParseError' do
        expect { described_class.parse(payload_without_head) }
          .to raise_error(PushEventParser::ParseError, /head/)
      end
    end

    context 'with nil payload' do
      it 'raises ParseError' do
        expect { described_class.parse(nil) }
          .to raise_error(PushEventParser::ParseError)
      end
    end
  end
end
