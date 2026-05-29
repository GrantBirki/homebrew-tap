# frozen_string_literal: true

require "spec_helper"

RSpec.describe "command objects" do
  def minimal_project
    write(".bundle/config", <<~YAML)
      ---
      BUNDLE_PATH: "vendor/gems"
      BUNDLE_CACHE_PATH: "vendor/cache"
      BUNDLE_NO_INSTALL: "true"
      BUNDLE_FROZEN: "true"
    YAML
    write("Gemfile.lock", <<~LOCK)
      GEM
        remote: https://rubygems.org/
        specs:

      PLATFORMS
        ruby

      DEPENDENCIES

      CHECKSUMS

      BUNDLED WITH
         2.7.2
    LOCK
    write(".github/workflows/test.yml", "steps:\n  - uses: actions/checkout@#{'a' * 40}\n")
    body = (HomebrewTap::TestChecks::FORMULA_TOKENS.map { |token| %(brew "grantbirki/tap/#{token}") } +
      HomebrewTap::TestChecks::CASK_TOKENS.map { |token| %(cask "grantbirki/tap/#{token}") }).join("\n")
    write("Brewfile", body)
  end

  it "runs lint checks and handles help and unknown options" do
    stdout = StringIO.new
    expect(HomebrewTap::LintCommand.new(argv: ["--help"], out: stdout, err: StringIO.new).run).to eq(0)
    expect(stdout.string).to include("Usage: script/lint")

    stderr = StringIO.new
    expect(HomebrewTap::LintCommand.new(argv: ["--wat"], out: StringIO.new, err: stderr).run).to eq(2)
    expect(stderr.string).to include("Unknown option")

    write(".github/workflows/test.yml", "steps:\n  - uses: actions/checkout@#{'a' * 40}\n")
    fake = FakeRunner.new
    expect(HomebrewTap::LintCommand.new(argv: [], runner: fake, out: StringIO.new, err: StringIO.new, root: @root).run).to eq(0)
    style_command = fake.commands.find { |cmd| cmd[3, 2] == ["brew", "style"] }
    expect(style_command).not_to be_nil
    rubocop_command = fake.commands.find { |cmd| cmd.include?("rubocop") }
    expect(rubocop_command).not_to be_nil

    failing = FakeRunner.new(failures: [style_command])
    expect(HomebrewTap::LintCommand.new(argv: [], runner: failing, out: StringIO.new, err: StringIO.new, root: @root).run).to eq(1)
  end

  it "runs test checks without invoking rspec when requested" do
    minimal_project
    fake = FakeRunner.new
    stdout = StringIO.new

    expect(HomebrewTap::TestCommand.new(argv: ["--help"], out: stdout, err: StringIO.new).run).to eq(0)
    expect(stdout.string).to include("Usage: script/test")
    expect(HomebrewTap::TestCommand.new(argv: ["--skip-rspec"], runner: fake, out: StringIO.new, err: StringIO.new, root: @root).run).to eq(0)
    expect(fake.commands.none? { |cmd| cmd == ["bundle", "exec", "rspec", "spec"] }).to eq(true)
    expect do
      HomebrewTap::TestCommand.new(argv: ["--wat"], out: StringIO.new, err: StringIO.new).run
    end.to raise_error(SystemExit)

    write("Gemfile.lock", "no checksums")
    expect(HomebrewTap::TestCommand.new(argv: ["--skip-rspec"], runner: fake, out: StringIO.new, err: StringIO.new, root: @root).run).to eq(1)
  end
end
