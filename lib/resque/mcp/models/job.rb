# frozen_string_literal: true

module Resque
  module Mcp
    module Models
      # One job payload. Raw args are sealed — filtered access is the only
      # public surface, so no caller can serialize them unfiltered.
      class Job
        attr_reader :class_name, :queue, :run_at

        def initialize(class_name:, args:, queue: nil, run_at: nil)
          @class_name = class_name
          @args = args
          @queue = queue
          @run_at = run_at
        end

        # Key-based filtering runs here, before any presentation-layer
        # truncation, so a secret can't survive inside a truncated JSON
        # string. Each hash arg is filtered as its own root, so anchored
        # dot-notation filters (/\Acredit_card\.code\z/) match exactly as
        # in Rails log filtering. Only hash keys can match — bare
        # positional scalars pass through. A raising host filter (e.g. a
        # proc assuming string values) fails CLOSED: args are withheld
        # with an in-band mark, never leaked.
        #
        # Memoization assumes a Job never outlives its request (the
        # adapter is per-request): the filter config and a transient
        # fail-closed result are frozen in at first read. Revisit before
        # ever caching adapter results across requests.
        def filtered_args
          return @filtered_args if defined?(@filtered_args)
          @filtered_args = filter(Resque::Mcp.config.param_filter, @args)
        rescue => e
          @filtered_args = "[args withheld: filter_parameters raised #{e.class}]"
        end

        # Debug and generic-serialization surfaces must not undo the
        # sealing: the default #inspect renders @args, ActiveSupport's
        # Object#as_json/#to_json walk instance variables, and pp bypasses
        # #inspect via #pretty_print.
        def inspect
          "#<#{self.class.name} class_name=#{@class_name.inspect} " \
            "queue=#{@queue.inspect} run_at=#{@run_at.inspect} args=[sealed]>"
        end

        def pretty_print(pp)
          pp.text(inspect)
        end

        def as_json(_options = nil)
          {"class_name" => @class_name, "queue" => @queue, "run_at" => @run_at,
           "args" => filtered_args}
        end

        private

        def filter(param_filter, value)
          case value
          when Hash then param_filter.filter(value)
          when Array then value.map { |element| filter(param_filter, element) }
          else value
          end
        end
      end
    end
  end
end
