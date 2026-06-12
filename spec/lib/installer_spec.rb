# frozen_string_literal: true

require "spec_helper"

RSpec.describe HomebrewTap::Installer do
  def write_formula(token, version, revision: nil)
    revision_line = "  revision #{revision}\n" if revision
    write("Formula/#{token}.rb", <<~RUBY)
      class #{token.capitalize} < Formula
        version "#{version}"
      #{revision_line}end
    RUBY
  end

  def write_url_formula(token, version, revision: nil)
    revision_line = "  revision #{revision}\n" if revision
    write("Formula/#{token}.rb", <<~RUBY)
      class #{token.capitalize} < Formula
        url "https://example.com/#{token}-#{version}.tar.gz"
      #{revision_line}end
    RUBY
  end

  def write_tag_formula(token, version)
    write("Formula/#{token}.rb", <<~RUBY)
      class #{token.capitalize} < Formula
        url "https://example.com/#{token}.git",
            tag: "#{version}",
            revision: "#{"a" * 40}"
      end
    RUBY
  end

  def write_cask(token, version)
    write("Casks/#{token}.rb", <<~RUBY)
      cask "#{token}" do
        version "#{version}"
      end
    RUBY
  end

  def brewfile
    write("Brewfile", <<~BREWFILE)
      tap "grantbirki/tap"
      brew "grantbirki/tap/bash"
      brew "grantbirki/tap/missing"
      cask "grantbirki/tap/alacritty"
      cask "grantbirki/tap/santa"
    BREWFILE
    write_url_formula("bash", "5.3.9")
    write_formula("missing", "1.0.0")
    write_cask("alacritty", "0.17.0")
    write_cask("santa", "2026.4")
  end

  def formula_receipt(tap, version)
    { "source" => { "tap" => tap, "versions" => { "stable" => version } } }
  end

  def cask_receipt(tap, version)
    { "source" => { "tap" => tap, "version" => version } }
  end

  def runner(prefix:, extra_captures: {}, failures: [], available: true, brew_version: "Homebrew 6.0.0")
    FakeRunner.new(
      captures: {
        ["brew", "--prefix"] => prefix,
        ["brew", "--version"] => brew_version,
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
    status = described_class.new(
      argv: [],
      runner: FakeRunner.new(available: false),
      out: StringIO.new,
      err: stderr,
      repo_root: @root
    ).run
    expect(status).to eq(1)
    expect(stderr.string).to include("Homebrew is not installed")

    status = described_class.new(
      argv: [],
      runner: FakeRunner.new,
      out: StringIO.new,
      err: stderr,
      repo_root: @root
    ).run
    expect(status).to eq(1)
    expect(stderr.string).to include("Brewfile not found")
  end

  it "dry-runs bundle before repoints and reports versions, downgrades, privilege, and missing entries" do
    brewfile
    prefix = File.join(@root, "prefix")
    receipt(prefix, :brew, "bash", version: "5.3.15", body: formula_receipt("homebrew/core", "5.3.15"))
    receipt(prefix, :cask, "alacritty", body: cask_receipt("grantbirki/tap", "0.17.0"))
    receipt(prefix, :cask, "santa", body: cask_receipt("homebrew/cask", "2026.5"))
    stdout = StringIO.new
    fake = runner(prefix: prefix)

    status = described_class.new(
      argv: ["--dry-run"],
      runner: fake,
      out: stdout,
      err: StringIO.new,
      repo_root: @root
    ).run

    expect(status).to eq(0)
    expect(fake.commands).to eq([])
    expect(stdout.string).to include("would run: HOMEBREW_UPDATE_TO_TAG=1 brew update")
    expect(stdout.string).to include("would run: brew tap grantbirki/tap")
    expect(stdout.string).to include("brew bash: homebrew/core 5.3.15 -> grantbirki/tap 5.3.9 [DOWNGRADE]")
    expect(stdout.string).to include("cask alacritty: grantbirki/tap 0.17.0 -> grantbirki/tap 0.17.0")
    expect(stdout.string).to include("brew missing: not installed -> grantbirki/tap 1.0.0")
    expect(stdout.string).to include(
      "cask santa: homebrew/cask 2026.5 -> grantbirki/tap 2026.4 [PRIVILEGED] [DOWNGRADE]"
    )
    bundle = "would run: brew bundle install --file=#{File.join(@root, "Brewfile")}"
    reinstall = "would run: brew reinstall --formula grantbirki/tap/bash"
    expect(stdout.string.index(bundle)).to be < stdout.string.index(reinstall)
    expect(stdout.string).to include("Repoint summary: 1 tap-managed, 2 wrong-tap, 1 missing")
  end

  it "fails closed on an unknown receipt before any Homebrew mutation" do
    brewfile
    prefix = File.join(@root, "prefix")
    receipt(prefix, :brew, "bash", body: { "source" => {} })
    stderr = StringIO.new
    fake = runner(prefix: prefix)

    status = described_class.new(argv: [], runner: fake, out: StringIO.new, err: stderr, repo_root: @root).run

    expect(status).to eq(1)
    expect(fake.commands).to eq([])
    expect(stderr.string).to include("Refusing to change Homebrew state", "receipt source.tap is missing")
  end

  it "skips receipt inspection when there are no tap-qualified entries" do
    write("Brewfile", %(brew "gh"\ncask "visual-studio-code"\n))
    stdout = StringIO.new
    fake = runner(prefix: File.join(@root, "prefix"))

    status = described_class.new(
      argv: ["--dry-run", "--no-update"],
      runner: fake,
      out: stdout,
      err: StringIO.new,
      repo_root: @root
    ).run

    expect(status).to eq(0)
    expect(stdout.string).to include(
      "No grantbirki/tap Brewfile entries to inspect",
      "No grantbirki/tap Brewfile entries to repoint"
    )
    expect(fake.commands).to eq([])
  end

  it "bundles before repointing wrong-tap formulae and casks and validates final receipts" do
    brewfile
    prefix = File.join(@root, "prefix")
    bash_receipt = receipt(
      prefix,
      :brew,
      "bash",
      version: "5.3.15",
      body: formula_receipt("homebrew/core", "5.3.15")
    )
    receipt(prefix, :cask, "alacritty", body: cask_receipt("homebrew/cask", "0.16.1"))
    receipt(prefix, :cask, "santa", body: cask_receipt("grantbirki/tap", "2026.4"))
    stdout = StringIO.new
    fake = runner(prefix: prefix)
    original_run = fake.method(:run)
    install_bash = proc do
      FileUtils.rm_f(bash_receipt)
      receipt(prefix, :brew, "bash", version: "5.3.9", body: formula_receipt("grantbirki/tap", "5.3.9"))
    end
    install_alacritty = proc do
      receipt(prefix, :cask, "alacritty", body: cask_receipt("grantbirki/tap", "0.17.0"))
    end

    fake.define_singleton_method(:run) do |*cmd|
      result = original_run.call(*cmd)
      case cmd
      when [HomebrewTap::Installer::HOMEBREW_ENV, "brew", "reinstall", "--formula", "grantbirki/tap/bash"]
        install_bash.call
      when [HomebrewTap::Installer::HOMEBREW_ENV, "brew", "reinstall", "--cask", "grantbirki/tap/alacritty"]
        install_alacritty.call
      end
      result
    end

    status = described_class.new(argv: [], runner: fake, out: stdout, err: StringIO.new, repo_root: @root).run

    expect(status).to eq(0)
    bundle = [
      HomebrewTap::Installer::HOMEBREW_ENV,
      "brew", "bundle", "install", "--file=#{File.join(@root, "Brewfile")}"
    ]
    formula_reinstall = [
      HomebrewTap::Installer::HOMEBREW_ENV,
      "brew", "reinstall", "--formula", "grantbirki/tap/bash"
    ]
    cask_reinstall = [
      HomebrewTap::Installer::HOMEBREW_ENV,
      "brew", "reinstall", "--cask", "grantbirki/tap/alacritty"
    ]
    update = [HomebrewTap::Installer::UPDATE_ENV, "brew", "update"]
    expect(fake.commands).to include(update, bundle, formula_reinstall, cask_reinstall)
    expect(fake.commands.index(bundle)).to be < fake.commands.index(formula_reinstall)
    expect(stdout.string).to include("Repoint summary: 3 tap-managed, 1 missing")
  end

  it "fails final validation when reinstall does not change the receipt source" do
    write("Brewfile", %(brew "grantbirki/tap/bash"\n))
    write_formula("bash", "5.3.9")
    prefix = File.join(@root, "prefix")
    receipt(prefix, :brew, "bash", version: "5.3.15", body: formula_receipt("homebrew/core", "5.3.15"))
    stderr = StringIO.new
    fake = runner(prefix: prefix)

    status = described_class.new(argv: ["--no-update"], runner: fake, out: StringIO.new, err: stderr, repo_root: @root).run

    expect(status).to eq(1)
    expect(stderr.string).to include("Repoint validation failed", "brew bash is still sourced from homebrew/core 5.3.15")
  end

  it "refreshes the final summary after Brewfile installation" do
    write("Brewfile", <<~BREWFILE)
      tap "grantbirki/tap"
      brew "grantbirki/tap/bash"
      brew "grantbirki/tap/vector"
    BREWFILE
    write_url_formula("bash", "5.3.9")
    write_tag_formula("vector", "0.56.0")
    prefix = File.join(@root, "prefix")
    receipt(prefix, :brew, "bash", body: formula_receipt("grantbirki/tap", "5.3.9"))
    stdout = StringIO.new
    fake = runner(prefix: prefix)
    bundle_command = [
      HomebrewTap::Installer::HOMEBREW_ENV,
      "brew", "bundle", "install", "--file=#{File.join(@root, "Brewfile")}"
    ]
    original_run = fake.method(:run)
    install_vector = proc do
      receipt(prefix, :brew, "vector", body: formula_receipt("grantbirki/tap", "0.56.0"))
    end

    fake.define_singleton_method(:run) do |*cmd|
      result = original_run.call(*cmd)
      install_vector.call if cmd == bundle_command
      result
    end

    status = described_class.new(argv: [], runner: fake, out: stdout, err: StringIO.new, repo_root: @root).run

    expect(status).to eq(0)
    expect(stdout.string).to include("brew vector: not installed -> grantbirki/tap 0.56.0")
    expect(stdout.string).to include("Repoint summary: 2 tap-managed")
    expect(stdout.string).not_to include("1 missing")
  end

  it "taps the current checkout when the tap is missing" do
    write("Brewfile", %(tap "grantbirki/tap"\n))
    fake = runner(
      prefix: File.join(@root, "prefix"),
      extra_captures: { ["brew", "--repo", "grantbirki/tap"] => ["", @root] }
    )

    status = described_class.new(argv: ["--no-update"], runner: fake, out: StringIO.new, err: StringIO.new, repo_root: @root).run

    expect(status).to eq(0)
    expect(fake.commands).to include(
      [HomebrewTap::Installer::HOMEBREW_ENV, "brew", "tap", "grantbirki/tap", @root]
    )
  end

  it "does not treat a conventional missing tap path as installed" do
    write("Brewfile", %(tap "grantbirki/tap"\n))
    missing_tap_path = File.join(@root, "missing", "homebrew-tap")
    fake = runner(
      prefix: File.join(@root, "prefix"),
      extra_captures: { ["brew", "--repo", "grantbirki/tap"] => [missing_tap_path, @root] }
    )

    status = described_class.new(argv: ["--no-update"], runner: fake, out: StringIO.new, err: StringIO.new, repo_root: @root).run

    expect(status).to eq(0)
    expect(fake.commands).to include(
      [HomebrewTap::Installer::HOMEBREW_ENV, "brew", "tap", "grantbirki/tap", @root]
    )
  end

  it "can skip update and repointing" do
    write("Brewfile", %(brew "grantbirki/tap/bash"\n))
    write_formula("bash", "5.3.9")
    prefix = File.join(@root, "prefix")
    receipt(prefix, :brew, "bash", version: "latest", body: formula_receipt("homebrew/core", "latest"))
    stdout = StringIO.new
    fake = runner(prefix: prefix)

    status = described_class.new(
      argv: ["--no-update", "--no-repoint"],
      runner: fake,
      out: stdout,
      err: StringIO.new,
      repo_root: @root
    ).run

    expect(status).to eq(0)
    expect(fake.commands).not_to include([HomebrewTap::Installer::UPDATE_ENV, "brew", "update"])
    expect(fake.commands).not_to include(
      [HomebrewTap::Installer::HOMEBREW_ENV, "brew", "reinstall", "--formula", "grantbirki/tap/bash"]
    )
    expect(stdout.string).to include("Skipping brew update", "Skipping repoint for grantbirki/tap/bash")
  end

  it "falls back to tapping by name when path tapping fails and reports command failures" do
    write("Brewfile", %(tap "grantbirki/tap"\n))
    path_tap = [HomebrewTap::Installer::HOMEBREW_ENV, "brew", "tap", "grantbirki/tap", @root]
    name_tap = [HomebrewTap::Installer::HOMEBREW_ENV, "brew", "tap", "grantbirki/tap"]
    fake = runner(
      prefix: File.join(@root, "prefix"),
      extra_captures: { ["brew", "--repo", "grantbirki/tap"] => ["", @root] },
      failures: [path_tap]
    )

    status = described_class.new(argv: [], runner: fake, out: StringIO.new, err: StringIO.new, repo_root: @root).run

    expect(status).to eq(0)
    expect(fake.commands).to include(path_tap, name_tap)

    stderr = StringIO.new
    update = [HomebrewTap::Installer::UPDATE_ENV, "brew", "update"]
    failing = runner(prefix: File.join(@root, "prefix"), failures: [update])
    status = described_class.new(argv: [], runner: failing, out: StringIO.new, err: stderr, repo_root: @root).run
    expect(status).to eq(1)
    expect(stderr.string).to include("command failed")
  end

  it "requires Homebrew 6 or newer even when update is skipped" do
    write("Brewfile", %(tap "grantbirki/tap"\n))
    stderr = StringIO.new
    fake = runner(prefix: File.join(@root, "prefix"), brew_version: "Homebrew 5.1.0")

    status = described_class.new(argv: ["--no-update"], runner: fake, out: StringIO.new, err: stderr, repo_root: @root).run

    expect(status).to eq(1)
    expect(fake.commands).to eq([])
    expect(stderr.string).to include("Homebrew 6 or newer is required; found Homebrew 5.1.0")

    unknown = runner(prefix: File.join(@root, "prefix"), brew_version: "")
    status = described_class.new(argv: ["--no-update"], runner: unknown, out: StringIO.new, err: stderr, repo_root: @root).run
    expect(status).to eq(1)
    expect(stderr.string).to include("found an unknown version")
  end

  it "fails when a local package definition or target version is missing" do
    write("Brewfile", %(brew "grantbirki/tap/missing"\n))
    stderr = StringIO.new
    fake = runner(prefix: File.join(@root, "prefix"))

    status = described_class.new(argv: [], runner: fake, out: StringIO.new, err: stderr, repo_root: @root).run
    expect(status).to eq(1)
    expect(stderr.string).to include("Package definition not found")

    write("Formula/missing.rb", "class Missing < Formula\nend\n")
    status = described_class.new(argv: [], runner: fake, out: StringIO.new, err: stderr, repo_root: @root).run
    expect(status).to eq(1)
    expect(stderr.string).to include("Could not determine the target version")
  end

  it "includes formula revisions in reported target versions" do
    write("Brewfile", %(brew "grantbirki/tap/rustup"\n))
    write_url_formula("rustup", "1.29.0", revision: 1)
    prefix = File.join(@root, "prefix")
    receipt(prefix, :brew, "rustup", version: "1.29.0_1", body: formula_receipt("grantbirki/tap", "1.29.0_1"))
    stdout = StringIO.new

    status = described_class.new(
      argv: ["--dry-run", "--no-update"],
      runner: runner(prefix: prefix),
      out: stdout,
      err: StringIO.new,
      repo_root: @root
    ).run

    expect(status).to eq(0)
    expect(stdout.string).to include("grantbirki/tap 1.29.0_1 -> grantbirki/tap 1.29.0_1")
  end
end
