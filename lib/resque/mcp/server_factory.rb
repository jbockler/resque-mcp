# frozen_string_literal: true

module Resque
  module Mcp
    # Builds a fresh ::MCP::Server per request. The caller passes
    # `environment` (the controller sends Rails.env); this file is Rails-free.
    module ServerFactory
      def self.build(environment: nil)
        ::MCP::Server.new(
          name: "resque-mcp",
          version: Resque::Mcp::VERSION,
          tools: [Tools::Overview, Tools::QueueStats],
          server_context: {adapter: Adapter.new, environment: environment}
        )
      end
    end
  end
end
