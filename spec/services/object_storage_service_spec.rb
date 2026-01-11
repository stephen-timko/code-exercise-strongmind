require 'rails_helper'

RSpec.describe ObjectStorageService do
  let(:event_id) { '12345' }
  let(:payload) { { 'id' => event_id, 'type' => 'PushEvent', 'actor' => { 'login' => 'testuser' } } }
  let(:s3_key) { "events/#{Time.current.strftime('%Y/%m/%d')}/#{event_id}.json" }
  let(:s3_client) { instance_double(Aws::S3::Client) }
  let(:bucket_name) { 'test-bucket' }

  before do
    # Stub configuration
    allow(ObjectStorage::Config).to receive(:ENABLED).and_return(true)
    allow(ObjectStorage::Config).to receive(:BUCKET).and_return(bucket_name)
    allow(ObjectStorage::Config).to receive(:REGION).and_return('us-east-1')
    allow(ObjectStorage::Config).to receive(:ACCESS_KEY_ID).and_return('test-key')
    allow(ObjectStorage::Config).to receive(:SECRET_ACCESS_KEY).and_return('test-secret')
    allow(ObjectStorage::Config).to receive(:ENDPOINT).and_return(nil)

    # Stub S3 client creation
    allow_any_instance_of(described_class).to receive(:build_s3_client).and_return(s3_client)
  end

  describe '.store' do
    context 'when S3 is enabled' do
      let(:put_response) { double('PutObjectResponse') }

      before do
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
        allow(ObjectStorage::Config).to receive(:ENABLED).and_return(false)
      end

      it 'returns nil (indicating JSONB fallback)' do
        result = described_class.store(event_id, payload)

        expect(result).to be_nil
        expect(s3_client).not_to have_received(:put_object)
      end
    end
  end

  describe '.retrieve' do
    context 'with existing key' do
      let(:get_response) { double('GetObjectResponse') }
      let(:body_io) { StringIO.new(payload.to_json) }

      before do
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
        allow(ObjectStorage::Config).to receive(:ENABLED).and_return(false)
      end

      it 'returns false' do
        result = described_class.delete(s3_key)

        expect(result).to be false
        expect(s3_client).not_to have_received(:delete_object)
      end
    end
  end

  describe 'S3 client configuration' do
    let(:service) { described_class.new }

    context 'with custom endpoint (localstack)' do
      before do
        allow(ObjectStorage::Config).to receive(:ENABLED).and_return(true)
        allow(ObjectStorage::Config).to receive(:ENDPOINT).and_return('http://localhost:4566')
        allow(ObjectStorage::Config).to receive(:REGION).and_return('us-east-1')
        allow(ObjectStorage::Config).to receive(:ACCESS_KEY_ID).and_return('test')
        allow(ObjectStorage::Config).to receive(:SECRET_ACCESS_KEY).and_return('test')
        allow(Aws::S3::Client).to receive(:new).and_return(s3_client)
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
      before do
        allow(ObjectStorage::Config).to receive(:ENABLED).and_return(true)
        allow(ObjectStorage::Config).to receive(:ENDPOINT).and_return(nil)
        allow(ObjectStorage::Config).to receive(:REGION).and_return('us-east-1')
        allow(ObjectStorage::Config).to receive(:ACCESS_KEY_ID).and_return('access-key')
        allow(ObjectStorage::Config).to receive(:SECRET_ACCESS_KEY).and_return('secret-key')
        allow(Aws::Credentials).to receive(:new).and_call_original
        allow(Aws::S3::Client).to receive(:new).and_return(s3_client)
      end

      it 'uses provided credentials' do
        described_class.new

        expect(Aws::Credentials).to have_received(:new).with('access-key', 'secret-key')
      end
    end
  end
end
