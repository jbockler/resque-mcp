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
          tools: [Tools::Overview, Tools::QueueStats, Tools::WorkerStats, Tools::ListFailures, Tools::GetFailure],
          # Explicit, or the SDK advertises `listChanged`/`subscribe` streams
          # we decline. This hash replaces the defaults and the SDK refuses
          # methods whose key is absent — hence the empty prompts/resources.
          capabilities: {tools: {}, prompts: {}, resources: {}, logging: {}},
          server_context: {adapter: Adapter.new, environment: environment}
        )
      end
    end
  end
end
