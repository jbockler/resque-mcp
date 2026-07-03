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
    end
  end
end
