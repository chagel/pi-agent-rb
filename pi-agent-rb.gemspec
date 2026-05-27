# frozen_string_literal: true

require_relative "lib/pi_agent/version"

Gem::Specification.new do |spec|
  spec.name = "pi-agent-rb"
  spec.version = PiAgent::VERSION
  spec.authors = ["chagel"]
  spec.email = []

  spec.summary = "Ruby client for the pi coding agent (drives `pi --mode rpc`)"
  spec.description = <<~DESC
    Ruby client for `@earendil-works/pi-coding-agent`. Spawns the pi CLI in RPC
    mode and speaks its JSONL protocol from Ruby. Designed for building
    interactive agent UIs (web, TUI) on top of pi.

    Not officially maintained by the pi project.
  DESC
  spec.homepage = "https://github.com/chagel/pi-agent-rb"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*", "README.md", "LICENSE", "CHANGELOG.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "async", "~> 2.0"
  # base64 left the default gem set in Ruby 3.4.
  spec.add_dependency "base64", "~> 0.2"
end
