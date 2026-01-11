FactoryBot.define do
  factory :github_event do
    event_id { Faker::Number.unique.number(digits: 10).to_s }
    event_type { 'PushEvent' }
    raw_payload do
      {
        'id' => event_id,
        'type' => event_type,
        'actor' => {
          'id' => Faker::Number.number(digits: 8),
          'login' => Faker::Internet.username,
          'url' => "https://api.github.com/users/#{Faker::Internet.username}"
        },
        'repo' => {
          'id' => Faker::Number.number(digits: 8),
          'name' => "#{Faker::Internet.username}/#{Faker::App.name.parameterize}",
          'full_name' => "#{Faker::Internet.username}/#{Faker::App.name.parameterize}",
          'url' => "https://api.github.com/repos/#{Faker::Internet.username}/#{Faker::App.name.parameterize}"
        },
        'payload' => {
          'push_id' => Faker::Number.number(digits: 10),
          'ref' => 'refs/heads/main',
          'head' => Faker::Crypto.sha256,
          'before' => Faker::Crypto.sha256
        }
      }
    end
    ingested_at { Time.current }
    processed_at { nil }

    trait :processed do
      processed_at { Time.current }
    end

    trait :with_push_event do
      after(:create) do |github_event|
        create(:push_event, github_event: github_event)
      end
    end
  end
end
