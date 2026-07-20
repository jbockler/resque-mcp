# frozen_string_literal: true

require "test_helper"
require "ipaddr"

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

      def test_allowed_hosts_without_a_source_are_empty
        config = Configuration.new
        assert_equal [], config.allowed_hosts
        assert_equal [], config.allowed_origins
      end

      def test_allowed_hosts_inherit_the_rails_config_hosts
        config = Configuration.new
        config.default_allowed_hosts = -> { ["resque.example.com", "admin.example.com"] }
        assert_equal ["resque.example.com", "admin.example.com"], config.allowed_hosts
      end

      # config.hosts entries the SDK's exact-hostname matching can't use —
      # regexps, IPAddrs, leading-dot subdomain wildcards — are skipped.
      def test_allowed_hosts_inheritance_skips_unmappable_entries
        config = Configuration.new
        config.default_allowed_hosts = -> {
          ["resque.example.com", /.*\.internal/, IPAddr.new("10.0.0.0/8"), ".example.com"]
        }
        assert_equal ["resque.example.com"], config.allowed_hosts
      end

      def test_explicit_allowed_hosts_replace_the_inherited_list
        config = Configuration.new
        config.default_allowed_hosts = -> { ["inherited.example.com"] }
        config.allowed_hosts = ["explicit.example.com"]
        assert_equal ["explicit.example.com"], config.allowed_hosts
      end

      # An explicit list is filtered too — a regexp (a natural mistake, since
      # config.hosts accepts them) would otherwise crash the transport's
      # downcase on every request.
      def test_explicit_allowed_hosts_drop_unmappable_entries
        config = Configuration.new
        config.allowed_hosts = ["resque.example.com", /admin\.example\.com/, ".example.com"]
        assert_equal ["resque.example.com"], config.allowed_hosts
      end

      def test_empty_allowed_hosts_disable_inheritance
        config = Configuration.new
        config.default_allowed_hosts = -> { ["inherited.example.com"] }
        config.allowed_hosts = []
        assert_equal [], config.allowed_hosts
      end

      def test_engine_wires_config_hosts_as_the_lazy_default
        assert_respond_to Resque::Mcp.config.default_allowed_hosts, :call
        assert_equal Rails.application.config.hosts, Resque::Mcp.config.default_allowed_hosts.call
      end

      def test_allowed_origins_are_configurable
        config = Configuration.new
        config.allowed_origins = ["https://resque.example.com"]
        assert_equal ["https://resque.example.com"], config.allowed_origins
      end

      def test_mcp_transport_options_default_empty_and_configurable
        config = Configuration.new
        assert_equal({}, config.mcp_transport_options)
        config.mcp_transport_options = {max_request_bytes: 1_000}
        assert_equal({max_request_bytes: 1_000}, config.mcp_transport_options)
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
