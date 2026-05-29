# frozen_string_literal: true

require "spec_helper"

RSpec.describe HomebrewTap::Installer do
  def brewfile
    write("Brewfile", <<~BREWFILE)
      tap "grantbirki/tap"
      brew "grantbirki/tap/bash"
      brew "grantbirki/tap/missing"
      cask "grantbirki/tap/alacritty"
      cask "grantbirki/tap/unknown"
    BREWFILE
  end

  def runner(prefix:, extra_captures: {}, failures: [], available: true)
    FakeRunner.new(
      captures: {
        ["brew", "--prefix"] => prefix,
        ["brew", "--repo", "grantbirki/tap"] => @root
      }.merge(extra_captures),
      failures: failures,
      available: available
    )
  end

  it "prints help" do
    stdout = StringIO.new

    status = described_class.new(argv: ["--help"], out: stdout, err: StringIO.new, repo_root: @root).run

    expect(status).to eq(0)
    expect(stdout.string).to include("Usage: script/install", "--no-repoint")
  end

  it "rejects unknown options and missing prerequisites" do
    expect do
      described_class.new(argv: ["--wat"], out: StringIO.new, err: StringIO.new, repo_root: @root).run
    end.to raise_error(SystemExit)

    stderr = StringIO.new
    status = described_class.new(argv: [], runner: FakeRunner.new(available: false), out: StringIO.new, err: stderr, repo_root: @root).run
    expect(status).to eq(1)
    expect(stderr.string).to include("Homebrew is not installed")

    status = described_class.new(argv: [], runner: FakeRunner.new, out: StringIO.new, err: stderr, repo_root: @root).run
    expect(status).to eq(1)
    expect(stderr.string).to include("Brewfile not found")
  end

  it "dry-runs updates, repoints, unknown receipts, missing entries, and bundle install" do
    brewfile
    prefix = File.join(@root, "prefix")
    receipt(prefix, :brew, "bash", body: { "source" => { "tap" => "homebrew/core" } })
    receipt(prefix, :cask, "alacritty", body: { "source" => { "tap" => "grantbirki/tap" } })
    receipt(prefix, :cask, "unknown", body: { "source" => {} })
    stdout = StringIO.new
    fake = runner(prefix: prefix)

    status = described_class.new(argv: ["--dry-run"], runner: fake, out: stdout, err: StringIO.new, repo_root: @root).run

    expect(status).to eq(0)
    expect(fake.commands).to eq([])
    expect(stdout.string).to include("would tap grantbirki/tap")
    expect(stdout.string).to include("would run: brew update")
    expect(stdout.string).to include("wrong tap brew: grantbirki/tap/bash is from homebrew/core")
    expect(stdout.string).to include("would run: brew reinstall --formula grantbirki/tap/bash")
    expect(stdout.string).to include("already tap-managed cask: grantbirki/tap/alacritty")
    expect(stdout.string).to include("missing brew: grantbirki/tap/missing")
    expect(stdout.string).to include("unknown receipt cask: grantbirki/tap/unknown")
    expect(stdout.string).to include("would run: brew bundle install --file=#{File.join(@root, "Brewfile")}")
  end

  it "repoints wrong-tap formulae and casks by default" do
    brewfile
    prefix = File.join(@root, "prefix")
    receipt(prefix, :brew, "bash", body: { "source" => { "tap" => "homebrew/core" } })
    receipt(prefix, :cask, "alacritty", body: { "source" => { "tap" => "homebrew/cask" } })
    fake = runner(prefix: prefix)

    status = described_class.new(argv: [], runner: fake, out: StringIO.new, err: StringIO.new, repo_root: @root).run

    expect(status).to eq(0)
    expect(fake.commands).to include(["brew", "tap", "grantbirki/tap", @root])
    expect(fake.commands).to include(["brew", "update"])
    expect(fake.commands).to include(["brew", "reinstall", "--formula", "grantbirki/tap/bash"])
    expect(fake.commands).to include(["brew", "reinstall", "--cask", "grantbirki/tap/alacritty"])
    expect(fake.commands).to include(["brew", "bundle", "install", "--file=#{File.join(@root, "Brewfile")}"])
  end

  it "can skip update and repointing" do
    brewfile
    prefix = File.join(@root, "prefix")
    receipt(prefix, :brew, "bash", body: { "source" => { "tap" => "homebrew/core" } })
    stdout = StringIO.new
    fake = runner(prefix: prefix)

    status = described_class.new(argv: ["--no-update", "--no-repoint"], runner: fake, out: stdout, err: StringIO.new, repo_root: @root).run

    expect(status).to eq(0)
    expect(fake.commands).not_to include(["brew", "update"])
    expect(fake.commands).not_to include(["brew", "reinstall", "--formula", "grantbirki/tap/bash"])
    expect(stdout.string).to include("Skipping brew update.", "skipping repoint for grantbirki/tap/bash")
  end

  it "falls back to tapping by name and reports command failures" do
    brewfile
    fake = runner(prefix: File.join(@root, "prefix"), failures: [["brew", "tap", "grantbirki/tap", @root]])

    status = described_class.new(argv: [], runner: fake, out: StringIO.new, err: StringIO.new, repo_root: @root).run

    expect(status).to eq(0)
    expect(fake.commands[0, 2]).to eq([
      ["brew", "tap", "grantbirki/tap", @root],
      ["brew", "tap", "grantbirki/tap"]
    ])

    stderr = StringIO.new
    failing = runner(prefix: File.join(@root, "prefix"), failures: [["brew", "update"]])
    status = described_class.new(argv: [], runner: failing, out: StringIO.new, err: stderr, repo_root: @root).run
    expect(status).to eq(1)
    expect(stderr.string).to include("command failed")
  end
end
