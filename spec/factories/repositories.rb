FactoryBot.define do
  factory :repository do
    github_id { Faker::Number.unique.number(digits: 8).to_s }
    full_name { "#{Faker::Internet.username}/#{Faker::App.name.parameterize}" }
    description { Faker::Lorem.sentence }
    raw_data do
      {
        'id' => github_id.to_i,
        'full_name' => full_name,
        'description' => description,
        'private' => false,
        'fork' => false
      }
    end
    fetched_at { Time.current }

    trait :stale do
      fetched_at { 25.hours.ago }
    end
  end
end
