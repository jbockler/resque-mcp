# frozen_string_literal: true

Resque::Mcp.configure do |c|
  c.auth_token = "test-token"
  # DNS-rebinding protection is on by default; integration tests drive the
  # endpoint as www.example.com. Set explicitly (rather than inheriting
  # config.hosts) so the tests exercise our transport gate in isolation from
  # Rails' own HostAuthorization. Inheritance is covered by unit tests.
  c.allowed_hosts = ["www.example.com"]
end
