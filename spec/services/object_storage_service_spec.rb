require 'rails_helper'

RSpec.describe ObjectStorageService do
  include ActiveSupport::Testing::TimeHelpers

  let(:event_id) { '12345' }
  let(:payload) { { 'id' => event_id, 'type' => 'PushEvent', 'actor' => { 'login' => 'testuser' } } }
  let(:s3_key) { "events/#{Time.current.strftime('%Y/%m/%d')}/#{event_id}.json" }
  let(:s3_client) { instance_double(Aws::S3::Client) }
  let(:bucket_name) { 'test-bucket' }

  before do
    # Stub S3 client creation
    allow_any_instance_of(described_class).to receive(:build_s3_client).and_return(s3_client)
  end

  describe '.store' do
    context 'when S3 is enabled' do
      let(:put_response) { double('PutObjectResponse') }

      before do
        stub_const('ObjectStorage::Config::ENABLED', true)
        stub_const('ObjectStorage::Config::BUCKET', bucket_name)
        stub_const('ObjectStorage::Config::REGION', 'us-east-1')
        stub_const('ObjectStorage::Config::ACCESS_KEY_ID', 'test-key')
        stub_const('ObjectStorage::Config::SECRET_ACCESS_KEY', 'test-secret')
        stub_const('ObjectStorage::Config::ENDPOINT', nil)
        allow(s3_client).to receive(:put_object).and_return(put_response)
      end

      it 'stores payload in S3 and returns the key' do
        result = described_class.store(event_id, payload)

        expect(result).to eq(s3_key)
        expect(s3_client).to have_received(:put_object).with(
          bucket: bucket_name,
          key: s3_key,
          body: payload.to_json,
          content_type: 'application/json'
        )
      end

      it 'generates keys with timestamp prefix' do
        freeze_time = Time.parse('2026-01-15 10:30:00 UTC')
        travel_to freeze_time do
          expected_key = "events/2026/01/15/#{event_id}.json"
          result = described_class.store(event_id, payload)

          expect(result).to eq(expected_key)
        end
      end

      context 'with S3 storage error' do
        before do
          allow(s3_client).to receive(:put_object).and_raise(
            Aws::S3::Errors::ServiceError.new(nil, 'Access Denied')
          )
        end

        it 'raises StorageError' do
          expect {
            described_class.store(event_id, payload)
          }.to raise_error(ObjectStorageService::StorageError, /S3 storage failed/)
        end
      end
    end

    context 'when S3 is disabled' do
      before do
        stub_const('ObjectStorage::Config::ENABLED', false)
      end

      it 'returns nil (indicating JSONB fallback)' do
        result = described_class.store(event_id, payload)

        expect(result).to be_nil
      end
    end
  end

  describe '.retrieve' do
    context 'with existing key' do
      let(:get_response) { double('GetObjectResponse') }
      let(:body_io) { StringIO.new(payload.to_json) }

      before do
        stub_const('ObjectStorage::Config::ENABLED', true)
        stub_const('ObjectStorage::Config::BUCKET', bucket_name)
        allow(get_response).to receive(:body).and_return(body_io)
        allow(s3_client).to receive(:get_object).with(
          bucket: bucket_name,
          key: s3_key
        ).and_return(get_response)
      end

      it 'retrieves payload from S3' do
        result = described_class.retrieve(s3_key)

        expect(result).to eq(payload)
        expect(s3_client).to have_received(:get_object).with(
          bucket: bucket_name,
          key: s3_key
        )
      end
    end

    context 'with non-existent key' do
      before do
        stub_const('ObjectStorage::Config::ENABLED', true)
        stub_const('ObjectStorage::Config::BUCKET', bucket_name)
        allow(s3_client).to receive(:get_object).and_raise(
          Aws::S3::Errors::NoSuchKey.new(nil, 'The specified key does not exist.')
        )
      end

      it 'raises NotFoundError' do
        expect {
          described_class.retrieve(s3_key)
        }.to raise_error(ObjectStorageService::NotFoundError, /S3 key not found/)
      end
    end

    context 'with S3 service error' do
      before do
        stub_const('ObjectStorage::Config::ENABLED', true)
        stub_const('ObjectStorage::Config::BUCKET', bucket_name)
        allow(s3_client).to receive(:get_object).and_raise(
          Aws::S3::Errors::ServiceError.new(nil, 'Access Denied')
        )
      end

      it 'raises StorageError' do
        expect {
          described_class.retrieve(s3_key)
        }.to raise_error(ObjectStorageService::StorageError, /S3 retrieval failed/)
      end
    end
  end

  describe '.delete' do
    context 'when S3 is enabled' do
      let(:delete_response) { double('DeleteObjectResponse') }

      before do
        stub_const('ObjectStorage::Config::ENABLED', true)
        stub_const('ObjectStorage::Config::BUCKET', bucket_name)
        allow(s3_client).to receive(:delete_object).and_return(delete_response)
      end

      it 'deletes key from S3 and returns true' do
        result = described_class.delete(s3_key)

        expect(result).to be true
        expect(s3_client).to have_received(:delete_object).with(
          bucket: bucket_name,
          key: s3_key
        )
      end

      context 'with non-existent key' do
        before do
          allow(s3_client).to receive(:delete_object).and_raise(
            Aws::S3::Errors::NoSuchKey.new(nil, 'The specified key does not exist.')
          )
        end

        it 'returns false' do
          result = described_class.delete(s3_key)

          expect(result).to be false
        end
      end

      context 'with S3 service error' do
        before do
          allow(s3_client).to receive(:delete_object).and_raise(
            Aws::S3::Errors::ServiceError.new(nil, 'Access Denied')
          )
        end

        it 'raises StorageError' do
          expect {
            described_class.delete(s3_key)
          }.to raise_error(ObjectStorageService::StorageError, /S3 deletion failed/)
        end
      end
    end

    context 'when S3 is disabled' do
      before do
        stub_const('ObjectStorage::Config::ENABLED', false)
      end

      it 'returns false' do
        result = described_class.delete(s3_key)

        expect(result).to be false
      end
    end
  end

  describe 'S3 client configuration' do
    context 'with custom endpoint (localstack)' do
      let(:real_client) { double('Aws::S3::Client') }

      before do
        stub_const('ObjectStorage::Config::ENABLED', true)
        stub_const('ObjectStorage::Config::ENDPOINT', 'http://localhost:4566')
        stub_const('ObjectStorage::Config::REGION', 'us-east-1')
        stub_const('ObjectStorage::Config::ACCESS_KEY_ID', 'test')
        stub_const('ObjectStorage::Config::SECRET_ACCESS_KEY', 'test')
        allow(Aws::Credentials).to receive(:new).and_return(double('Credentials'))
        allow(Aws::S3::Client).to receive(:new).and_return(real_client)
        allow_any_instance_of(described_class).to receive(:build_s3_client).and_call_original
      end

      it 'configures client with custom endpoint and path style' do
        described_class.new

        expect(Aws::S3::Client).to have_received(:new).with(
          hash_including(
            endpoint: 'http://localhost:4566',
            force_path_style: true,
            region: 'us-east-1'
          )
        )
      end
    end

    context 'with credentials' do
      let(:credentials) { double('Aws::Credentials') }
      let(:real_client) { double('Aws::S3::Client') }

      before do
        stub_const('ObjectStorage::Config::ENABLED', true)
        stub_const('ObjectStorage::Config::ENDPOINT', nil)
        stub_const('ObjectStorage::Config::REGION', 'us-east-1')
        stub_const('ObjectStorage::Config::ACCESS_KEY_ID', 'access-key')
        stub_const('ObjectStorage::Config::SECRET_ACCESS_KEY', 'secret-key')
        allow(Aws::Credentials).to receive(:new).with('access-key', 'secret-key').and_return(credentials)
        allow(Aws::S3::Client).to receive(:new).and_return(real_client)
        allow_any_instance_of(described_class).to receive(:build_s3_client).and_call_original
      end

      it 'uses provided credentials' do
        described_class.new

        expect(Aws::Credentials).to have_received(:new).with('access-key', 'secret-key')
      end
    end
  end
end
