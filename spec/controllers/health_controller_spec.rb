require 'rails_helper'

RSpec.describe HealthController, type: :controller do
  describe 'GET #show' do
    it 'returns http success' do
      get :show
      expect(response).to have_http_status(:success)
    end

    it 'returns JSON with status and timestamp' do
      get :show
      json = JSON.parse(response.body)

      expect(json['status']).to eq('ok')
      expect(json['timestamp']).to be_present
    end

    it 'returns timestamp in ISO8601 format' do
      get :show
      json = JSON.parse(response.body)

      expect { Time.iso8601(json['timestamp']) }.not_to raise_error
    end

    it 'returns ok status' do
      get :show
      json = JSON.parse(response.body)

      expect(json['status']).to eq('ok')
    end
  end
end
