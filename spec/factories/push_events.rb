FactoryBot.define do
  factory :push_event do
    association :github_event
    repository_id { "#{Faker::Internet.username}/#{Faker::App.name.parameterize}" }
    push_id { Faker::Number.unique.number(digits: 10).to_s }
    ref { 'refs/heads/main' }
    head { Faker::Crypto.sha256 }
    enrichment_status { 'pending' }
    
    # Use after(:build) for 'before' field since it's a reserved keyword
    after(:build) do |push_event|
      push_event.before = Faker::Crypto.sha256 if push_event.before.blank?
    end

    trait :enriched do
      enrichment_status { 'completed' }
      association :actor
      association :enriched_repository, factory: :repository
    end

    trait :with_actor do
      association :actor
    end

    trait :with_repository do
      association :enriched_repository, factory: :repository
    end

    trait :failed do
      enrichment_status { 'failed' }
    end

    trait :in_progress do
      enrichment_status { 'in_progress' }
    end
  end
end
