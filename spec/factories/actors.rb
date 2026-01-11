FactoryBot.define do
  factory :actor do
    github_id { Faker::Number.unique.number(digits: 8).to_s }
    login { Faker::Internet.username }
    avatar_url { Faker::Internet.url }
    raw_data do
      {
        'id' => github_id.to_i,
        'login' => login,
        'avatar_url' => avatar_url,
        'type' => 'User',
        'site_admin' => false
      }
    end
    fetched_at { Time.current }

    trait :stale do
      fetched_at { 25.hours.ago }
    end
  end
end
