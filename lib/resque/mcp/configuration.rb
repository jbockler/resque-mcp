# frozen_string_literal: true

module Resque
  module Mcp
    class Configuration
      attr_accessor :auth_token
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
