# frozen_string_literal: true

require "test_helper"

module Resque
  module Mcp
    class ConfigurationTest < Minitest::Test
      include ResqueTestHelpers

      # The dummy app sets config.filter_parameters += [:password]; the
      # engine wires Rails' list as a lazy default source. Rails 7.1+
      # precompiles the list into regexes, so assert behavior, not the
      # literal :password symbol.
      def test_filter_parameters_default_to_the_rails_list
        assert_nil Resque::Mcp.config.filter_parameters, "explicit option stays unset; Rails is a lazy default"
        filtered = Resque::Mcp.config.param_filter.filter({"password" => "x"})
        assert_equal "[FILTERED]", filtered["password"]
      end

      # The Rails source is read lazily, not snapshotted at boot — an
      # engine or initializer extending the list later is never missed.
      def test_rails_list_changes_after_boot_are_picked_up
        rails_config = Rails.application.config
        original = rails_config.filter_parameters
        rails_config.filter_parameters = original + [:iban]

        filtered = Resque::Mcp.config.param_filter.filter({"iban" => "DE00"})
        assert_equal "[FILTERED]", filtered["iban"]
      ensure
        rails_config.filter_parameters = original
      end

      def test_in_place_mutation_of_the_list_takes_effect
        with_filter_parameters([:secret]) do
          Resque::Mcp.config.param_filter # prime the memo
          Resque::Mcp.config.filter_parameters << :iban

          filtered = Resque::Mcp.config.param_filter.filter({"iban" => "DE00"})
          assert_equal "[FILTERED]", filtered["iban"]
        end
      end

      def test_param_filter_reflects_the_configured_list
        with_filter_parameters([:secret]) do
          filtered = Resque::Mcp.config.param_filter.filter({"secret" => "x", "a" => 1})
          assert_equal({"secret" => "[FILTERED]", "a" => 1}, filtered)
        end
      end

      def test_param_filter_is_rebuilt_when_the_list_changes
        with_filter_parameters([:secret]) do
          before = Resque::Mcp.config.param_filter
          Resque::Mcp.config.filter_parameters = []
          refute_same before, Resque::Mcp.config.param_filter
          assert_equal({"secret" => "x"}, Resque::Mcp.config.param_filter.filter({"secret" => "x"}))
        end
      end

      def test_nil_falls_back_to_the_rails_default_and_empty_list_disables
        with_filter_parameters(nil) do
          assert_equal({"password" => "[FILTERED]"}, Resque::Mcp.config.param_filter.filter({"password" => "x"}))
        end
        with_filter_parameters([]) do
          assert_equal({"password" => "x"}, Resque::Mcp.config.param_filter.filter({"password" => "x"}))
        end
      end
    end
  end
end
