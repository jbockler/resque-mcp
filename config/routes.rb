# frozen_string_literal: true

Resque::Mcp::Engine.routes.draw do
  post "/", to: "endpoint#handle"
  match "/", to: "endpoint#method_not_allowed", via: :all
end
