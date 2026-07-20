# frozen_string_literal: true

module Resque
  module Mcp
    class Configuration
      attr_accessor :auth_token

      # DNS-rebinding protection (mcp >= 0.23, CVE-2026-63118). The transport
      # validates Host/Origin headers; loopback hosts are always allowed.
      #
      # nil (default) inherits the host's Rails config.hosts; an explicit list
      # replaces it; [] means loopback only. Either way, only plain hostname
      # strings are honored — regexps, IPAddrs, and leading-dot subdomain
      # wildcards (".example.com") can't map to the SDK's exact-hostname
      # matching (and a non-string would crash its downcase), so they're
      # dropped from both paths. allowed_origins adds extra permitted Origin
      # values beyond same-origin.
      attr_writer :allowed_hosts, :allowed_origins

      # Internal seam: a callable returning the host's config.hosts, read
      # lazily (the engine wires it) so post-boot changes are never missed.
      attr_accessor :default_allowed_hosts

      def allowed_hosts
        list = (defined?(@allowed_hosts) && @allowed_hosts) ? @allowed_hosts : default_allowed_hosts&.call
        Array(list).select { |h| h.is_a?(String) && !h.start_with?(".") }
      end

      def allowed_origins
        @allowed_origins || []
      end

      # nil = inherit the host default (the engine wires Rails'
      # filter_parameters as a lazy source); an explicit list replaces it
      # ([] disables filtering).
      attr_accessor :filter_parameters
      # Internal seam: a callable returning the host's filter list, read
      # lazily so late additions to Rails' list (or other engines'
      # after_initialize hooks) are never missed.
      attr_accessor :default_filter_parameters

      # Memoized against the *effective* list, so both reassignment and
      # in-place mutation (config.filter_parameters << :iban) take effect.
      def param_filter
        list = filter_parameters || default_filter_parameters&.call || []
        unless defined?(@param_filter) && @param_filter_list == list
          @param_filter_list = list.dup
          @param_filter = ActiveSupport::ParameterFilter.new(list)
        end
        @param_filter
      end
    end
  end
end
