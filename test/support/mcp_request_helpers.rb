# frozen_string_literal: true

# Shared JSON-RPC plumbing for integration tests; the auth token's source
# of truth is the dummy app initializer, read via Resque::Mcp.config.
module McpRequestHelpers
  ENDPOINT = "/resque-mcp"

  INITIALIZE_PARAMS = {
    protocolVersion: "2025-06-18",
    capabilities: {},
    clientInfo: {name: "test-client", version: "0.0.1"}
  }.freeze

  def post_jsonrpc(method:, params: {}, id: 1, authorization: default_authorization, host: nil, origin: nil)
    host!(host) if host
    headers = {"Content-Type" => "application/json", "Accept" => "application/json"}
    headers["Authorization"] = authorization if authorization
    headers["Origin"] = origin if origin

    post ENDPOINT,
      params: {jsonrpc: "2.0", id: id, method: method, params: params}.to_json,
      headers: headers
  end

  # The SEP-2575 sessionless lifecycle: no handshake, every request carries
  # its own protocol version in `_meta` and mirrors it in the headers.
  MODERN_PROTOCOL_VERSION = "2026-07-28"

  MODERN_META = {
    "io.modelcontextprotocol/protocolVersion" => MODERN_PROTOCOL_VERSION,
    "io.modelcontextprotocol/clientCapabilities" => {}
  }.freeze

  # The lifecycle landed in mcp 1.2; the gemspec still admits 0.x, where
  # these requests are answered with an unsupported-version error instead.
  def modern_lifecycle_supported?
    ::MCP::Configuration.const_defined?(:SUPPORTED_MODERN_PROTOCOL_VERSIONS)
  end

  def post_modern_jsonrpc(method:, params: {}, id: 1, authorization: default_authorization)
    headers = {
      "Content-Type" => "application/json",
      "Accept" => "application/json, text/event-stream",
      "MCP-Protocol-Version" => MODERN_PROTOCOL_VERSION,
      "Mcp-Method" => method
    }
    # The SDK validates the header against `params[:uri]` for uri-bearing
    # methods (`resources/read`), not just `params[:name]`.
    body_name = params[:name] || params[:uri]
    headers["Mcp-Name"] = body_name if body_name
    headers["Authorization"] = authorization if authorization

    post ENDPOINT,
      params: {
        jsonrpc: "2.0", id: id, method: method,
        params: params.merge(_meta: MODERN_META)
      }.to_json,
      headers: headers
  end

  def post_initialize(authorization: default_authorization)
    post_jsonrpc(method: "initialize", params: INITIALIZE_PARAMS, authorization: authorization)
  end

  def post_initialize_with_host(host)
    post_jsonrpc(method: "initialize", params: INITIALIZE_PARAMS, host: host)
  end

  def post_initialize_with_origin(origin)
    post_jsonrpc(method: "initialize", params: INITIALIZE_PARAMS, origin: origin)
  end

  def default_authorization
    "Bearer #{Resque::Mcp.config.auth_token}"
  end

  def with_mcp_transport_options(options)
    original = Resque::Mcp.config.mcp_transport_options
    Resque::Mcp.config.mcp_transport_options = options
    yield
  ensure
    Resque::Mcp.config.mcp_transport_options = original
  end
end
