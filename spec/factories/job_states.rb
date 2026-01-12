FactoryBot.define do
  factory :job_state do
    key { "test_key_#{Faker::Alphanumeric.alphanumeric(number: 10)}" }
    value { Faker::Lorem.word }
  end
end
