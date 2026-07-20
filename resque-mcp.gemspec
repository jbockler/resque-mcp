# frozen_string_literal: true

require_relative "lib/resque/mcp/version"

Gem::Specification.new do |spec|
  spec.name = "resque-mcp"
  spec.version = Resque::Mcp::VERSION
  spec.authors = ["Josch Bockler"]
  spec.email = ["9265647+jbockler@users.noreply.github.com"]

  spec.summary = "MCP server for Resque, mountable as a Rails engine."
  spec.description = "Exposes Resque queues, workers, and failed jobs to MCP clients " \
    "via a Streamable HTTP endpoint mounted in the host Rails app."
  spec.homepage = "https://github.com/jbockler/resque-mcp"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"
  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore test/ .github/ .standard.yml])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "resque", ">= 2.7", "< 4"
  spec.add_dependency "mcp", ">= 0.23", "< 1"
  spec.add_dependency "activesupport", ">= 7.2"
  spec.add_dependency "railties", ">= 7.2"
  spec.add_dependency "zeitwerk", ">= 2.6"
end
