# frozen_string_literal: true

require "rails/engine"

module Resque
  module Mcp
    class Engine < ::Rails::Engine
      isolate_namespace Resque::Mcp
    end
  end
end
