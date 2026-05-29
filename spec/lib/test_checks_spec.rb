# frozen_string_literal: true

require "spec_helper"

RSpec.describe HomebrewTap::TestChecks do
  def valid_lock
    <<~LOCK
      GEM
        remote: https://rubygems.org/
        specs:
          rspec (3.13.2)

      PLATFORMS
        ruby

      DEPENDENCIES
        rspec (= 3.13.2)

      CHECKSUMS
        rspec (3.13.2) sha256=#{'a' * 64}

      BUNDLED WITH
         2.7.2
    LOCK
  end

  def valid_bundle_files
    write(".bundle/config", <<~YAML)
      ---
      BUNDLE_PATH: "vendor/gems"
      BUNDLE_CACHE_PATH: "vendor/cache"
      BUNDLE_NO_INSTALL: "true"
      BUNDLE_FROZEN: "true"
    YAML
    write("Gemfile.lock", valid_lock)
    write("vendor/cache/rspec-3.13.2.gem", "")
  end

  it "validates Bundler supply-chain metadata and reports drift" do
    valid_bundle_files
    expect(described_class::BundlerSupplyChain.new(root: @root).validate).to eq(true)

    write(".bundle/config", "---\nBUNDLE_FROZEN: \"false\"\n")
    expect { described_class::BundlerSupplyChain.new(root: @root).validate }.to raise_error(HomebrewTap::Error, /BUNDLE_FROZEN/)

    valid_bundle_files
    write("Gemfile.lock", valid_lock.sub("CHECKSUMS\n", ""))
    expect { described_class::BundlerSupplyChain.new(root: @root).validate }.to raise_error(HomebrewTap::Error, /missing CHECKSUMS/)

    valid_bundle_files
    FileUtils.rm(File.join(@root, "vendor/cache/rspec-3.13.2.gem"))
    write("vendor/cache/extra-1.0.0.gem", "")
    expect { described_class::BundlerSupplyChain.new(root: @root).validate }.to raise_error(HomebrewTap::Error) do |error|
      expect(error.message).to include("missing cached gem: vendor/cache/rspec-3.13.2.gem")
      expect(error.message).to include("extra cached gem: vendor/cache/extra-1.0.0.gem")
    end

    valid_bundle_files
    write("Gemfile.lock", valid_lock.sub("  rspec (3.13.2) sha256=#{'a' * 64}\n", ""))
    expect { described_class::BundlerSupplyChain.new(root: @root).validate }.to raise_error(HomebrewTap::Error, /missing checksum/)
  end

  it "validates workflow pins" do
    write(".github/workflows/test.yml", "steps:\n  - uses: actions/checkout@#{'a' * 40}\n")
    expect(described_class::WorkflowPins.new(root: @root).validate).to eq(true)

    write(".github/workflows/lint.yml", "steps:\n  - uses: actions/checkout@v6\n")
    expect { described_class::WorkflowPins.new(root: @root).validate }.to raise_error(HomebrewTap::Error, /not SHA-pinned/)
  end

  it "runs syntax, cask, style, and Brewfile parse commands through the injected runner" do
    write("lib/homebrew_tap/example.rb", "")
    write("Formula/foo.rb", "")
    write("Casks/foo.rb", "")
    write("Brewfile", %(tap "grantbirki/tap"\n))
    write("script/install", "")
    write("script/lint", "")
    write("script/test", "")
    write("script/vendor", "")
    fake = FakeRunner.new

    expect(described_class::RubySyntax.new(root: @root, runner: fake).validate).to eq(true)
    expect(fake.commands).to include(["ruby", "-c", File.join(@root, "Formula/foo.rb")])

    expect(described_class::CaskParsing.new(root: @root, runner: fake).validate).to eq(true)
    cask_command = fake.commands.find { |cmd| cmd.any? { |part| part.include?("cask/cask_loader") } }
    expect(cask_command[0, 2]).to eq(["env", "HOMEBREW_NO_INSTALL_FROM_API=1"])
    expect(cask_command[2]).to start_with("HOMEBREW_CACHE=")
    expect(cask_command[3, 2]).to eq(["brew", "ruby"])
    expect(cask_command.join(" ")).to include("Homebrew::SimulateSystem.with")

    expect(described_class::HomebrewStyle.new(root: @root, runner: fake).validate).to eq(true)
    style_command = fake.commands.last
    expect(style_command[0, 2]).to eq(["env", "HOMEBREW_NO_INSTALL_FROM_API=1"])
    expect(style_command[2]).to start_with("HOMEBREW_CACHE=")
    expect(style_command[3, 2]).to eq(["brew", "style"])

    expect(described_class::BrewfileParsing.new(root: @root, runner: fake).validate).to eq(true)
    brewfile_command = fake.commands.last
    expect(brewfile_command[0, 2]).to eq(["env", "HOMEBREW_NO_INSTALL_FROM_API=1"])
    expect(brewfile_command[2]).to start_with("HOMEBREW_CACHE=")
    expect(brewfile_command[3, 3]).to eq(["brew", "ruby", "-e"])
    expect(brewfile_command).to include(File.join(@root, "Brewfile"))
    expect(brewfile_command.join(" ")).to include("Homebrew::Bundle::Dsl")
  end

  it "validates required Brewfile pins" do
    body = (described_class::FORMULA_TOKENS.map { |token| %(brew "grantbirki/tap/#{token}") } +
      described_class::CASK_TOKENS.map { |token| %(cask "grantbirki/tap/#{token}") }).join("\n")
    write("Brewfile", body)
    expect(described_class::BrewfilePins.new(root: @root).validate).to eq(true)

    write("Brewfile", %(brew "grantbirki/tap/bash"\n))
    expect { described_class::BrewfilePins.new(root: @root).validate }.to raise_error(HomebrewTap::Error, /Brewfile is missing/)
  end
end
