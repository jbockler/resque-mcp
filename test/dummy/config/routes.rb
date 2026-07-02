# frozen_string_literal: true

Rails.application.routes.draw do
  mount Resque::Mcp::Engine => "/resque-mcp"
end
