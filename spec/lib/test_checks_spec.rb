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
      BUNDLE_DISABLE_SHARED_GEMS: "true"
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

  it "runs syntax, formula, cask, style, and Brewfile parse commands through the injected runner" do
    write("lib/homebrew_tap/example.rb", "")
    write("Formula/foo.rb", "")
    write("Casks/foo.rb", "")
    write("Brewfile", %(tap "grantbirki/tap"\n))
    write("script/install", "#!/usr/bin/env bash\n")
    write("script/lint", "#!/usr/bin/env bash\n")
    write("script/empty", "")
    fake = FakeRunner.new

    expect(described_class::RubySyntax.new(root: @root, runner: fake).validate).to eq(true)
    expect(fake.commands).to include(["ruby", "-c", File.join(@root, "Formula/foo.rb")])

    expect(described_class::ShellSyntax.new(root: @root, runner: fake).validate).to eq(true)
    expect(fake.commands).to include(["bash", "-n", File.join(@root, "script/install")])

    expect(described_class::FormulaParsing.new(root: @root, runner: fake).validate).to eq(true)
    formula_command = fake.commands.last
    expect(formula_command).to include(
      "HOMEBREW_NO_AUTO_UPDATE=1",
      "HOMEBREW_REQUIRE_TAP_TRUST=1",
      "HOMEBREW_NO_INSTALL_FROM_API=1",
    )
    expect(formula_command.join(" ")).to include("Formulary.from_contents", "Homebrew::SimulateSystem.with")

    expect(described_class::CaskParsing.new(root: @root, runner: fake).validate).to eq(true)
    cask_command = fake.commands.find { |cmd| cmd.any? { |part| part.include?("cask/cask_loader") } }
    expect(cask_command[0]).to eq("env")
    expect(cask_command).to include(
      "HOMEBREW_NO_AUTO_UPDATE=1",
      "HOMEBREW_REQUIRE_TAP_TRUST=1",
      "HOMEBREW_NO_INSTALL_FROM_API=1",
    )
    expect(cask_command.any? { |part| part.start_with?("HOMEBREW_CACHE=") }).to eq(true)
    brew_index = cask_command.index("brew")
    expect(cask_command[brew_index, 2]).to eq(["brew", "ruby"])
    expect(cask_command.join(" ")).to include("Homebrew::SimulateSystem.with")

    expect(described_class::HomebrewStyle.new(root: @root, runner: fake).validate).to eq(true)
    style_command = fake.commands.last
    expect(style_command[0]).to eq("env")
    expect(style_command).to include("HOMEBREW_NO_AUTO_UPDATE=1", "HOMEBREW_REQUIRE_TAP_TRUST=1")
    expect(style_command.any? { |part| part.start_with?("HOMEBREW_CACHE=") }).to eq(true)
    brew_index = style_command.index("brew")
    expect(style_command[brew_index, 2]).to eq(["brew", "style"])

    expect(described_class::RuboCop.new(root: @root, runner: fake).validate).to eq(true)
    rubocop_command = fake.commands.last
    expect(rubocop_command[0]).to eq("env")
    expect(rubocop_command[1]).to eq("RUBOCOP_CACHE_ROOT=#{File.join(@root, "tmp/rubocop_cache")}")
    expect(rubocop_command[2, 5]).to eq(["bundle", "exec", "rubocop", "-c", File.join(@root, ".rubocop.yml")])
    expect(rubocop_command).to include(File.join(@root, "lib"))
    expect(rubocop_command).to include(File.join(@root, "spec"))
    expect(rubocop_command).not_to include(File.join(@root, "script/install"))
    expect(rubocop_command).not_to include(File.join(@root, "Formula"))
    expect(rubocop_command).not_to include(File.join(@root, "Casks"))

    expect(described_class::BrewfileParsing.new(root: @root, runner: fake).validate).to eq(true)
    brewfile_command = fake.commands.last
    expect(brewfile_command[0]).to eq("env")
    expect(brewfile_command).to include("HOMEBREW_NO_AUTO_UPDATE=1", "HOMEBREW_REQUIRE_TAP_TRUST=1")
    expect(brewfile_command.any? { |part| part.start_with?("HOMEBREW_CACHE=") }).to eq(true)
    brew_index = brewfile_command.index("brew")
    expect(brewfile_command[brew_index, 3]).to eq(["brew", "ruby", "-e"])
    expect(brewfile_command).to include(File.join(@root, "Brewfile"))
    expect(brewfile_command.join(" ")).to include("Homebrew::Bundle::Dsl")
  end

  it "validates required Brewfile pins" do
    body = (["tap \"grantbirki/tap\"", "cask_args require_sha: true"] +
      described_class::FORMULA_TOKENS.map { |token| %(brew "grantbirki/tap/#{token}", trusted: true) } +
      described_class::CASK_TOKENS.map { |token| %(cask "grantbirki/tap/#{token}", trusted: true) }).join("\n")
    write("Brewfile", body)
    expect(described_class::BrewfilePins.new(root: @root).validate).to eq(true)

    write("Brewfile", "#{body}\nbrew \"grantbirki/tap/extra\", trusted: true\n")
    expect { described_class::BrewfilePins.new(root: @root).validate }.to raise_error(HomebrewTap::Error, /unexpected brew/)

    write("Brewfile", "#{body}\nbrew \"grantbirki/tap/bash\", trusted: true\n")
    expect { described_class::BrewfilePins.new(root: @root).validate }.to raise_error(HomebrewTap::Error, /duplicates brew/)

    write("Brewfile", %(brew "grantbirki/tap/bash"\n))
    expect { described_class::BrewfilePins.new(root: @root).validate }.to raise_error(HomebrewTap::Error, /Brewfile is missing/)
  end

  it "rejects broad tap trust, missing item trust, and missing cask checksum policy" do
    body = ([%(tap "grantbirki/tap", trusted: true)] +
      described_class::FORMULA_TOKENS.map { |token| %(brew "grantbirki/tap/#{token}") } +
      described_class::CASK_TOKENS.map { |token| %(cask "grantbirki/tap/#{token}") }).join("\n")
    write("Brewfile", body)

    expect { described_class::BrewfilePins.new(root: @root).validate }.to raise_error(HomebrewTap::Error) do |error|
      expect(error.message).to include("must not trust the entire tap", "must set cask_args", "must set trusted: true")
    end
  end
end
