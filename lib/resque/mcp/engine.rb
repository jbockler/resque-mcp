# frozen_string_literal: true

require "rails/engine"

module Resque
  module Mcp
    class Engine < ::Rails::Engine
      isolate_namespace Resque::Mcp

      # A lazy source, not a boot-time snapshot: evaluated per use so
      # post-boot additions to Rails' filter list (or other engines'
      # after_initialize hooks) are never missed. An explicitly configured
      # filter_parameters still takes precedence.
      initializer "resque_mcp.filter_parameters" do
        Resque::Mcp.config.default_filter_parameters = -> { Rails.application.config.filter_parameters }
      end

      # allowed_hosts inherits the host's config.hosts (the same list Rails'
      # own host authorization uses) unless explicitly configured, read
      # lazily for the same reason as the filter list above.
      initializer "resque_mcp.allowed_hosts" do
        Resque::Mcp.config.default_allowed_hosts = -> { Rails.application.config.hosts }
      end
    end
  end
end
