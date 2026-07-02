# Changelog

## [Unreleased]

## [0.1.0]

- Mountable Rails engine serving a stateless MCP Streamable HTTP endpoint (`POST` only; all other verbs answer 405).
- `overview` tool: global Resque health snapshot (pending/processed/failed totals, queue count and sizes, worker counts) with an environment + Redis-target meta footer (Redis credentials stripped).
- Mandatory bearer-token auth: `Resque::Mcp.configure { |c| c.auth_token = … }`; unauthenticated requests get 401 + `WWW-Authenticate: Bearer`, a blank configured token gets 503.
