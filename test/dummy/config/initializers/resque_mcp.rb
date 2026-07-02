# frozen_string_literal: true

Resque::Mcp.configure do |c|
  c.auth_token = "test-token"
end
