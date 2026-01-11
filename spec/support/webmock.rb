require 'webmock/rspec'

# Disable real HTTP connections in tests, except for localhost
WebMock.disable_net_connect!(allow_localhost: true)
