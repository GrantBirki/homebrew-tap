# frozen_string_literal: true

require "spec_helper"
require "rbconfig"

RSpec.describe "script entrypoints" do
  it "loads development command help through the project Ruby" do
    %w[lint test vendor provenance].each do |name|
      stdout, stderr, status = Open3.capture3(
        { "RBENV_VERSION" => File.read(File.join(ROOT, ".ruby-version")).strip },
        File.join(ROOT, "script", name),
        "--help",
        chdir: ROOT,
      )
      expect(status).to be_success, stderr
      expect(stdout).to include("script/#{name}")
    end
  end

  it "runs the install entrypoint through brew ruby" do
    bin = File.join(@root, "bin")
    FileUtils.mkdir_p(bin)
    write("bin/brew", <<~SH)
      #!/usr/bin/env bash
      test "$1" = "ruby"
      shift
      exec "#{RbConfig.ruby}" "$@"
    SH
    FileUtils.chmod("u+x", File.join(bin, "brew"))

    stdout, stderr, status = Open3.capture3(
      { "PATH" => "#{bin}:#{ENV.fetch("PATH")}" },
      File.join(ROOT, "script", "install"),
      "--help",
    )

    expect(status).to be_success
    expect(stdout).to include("Usage: script/install")
    expect(stderr).to be_empty
  end

  it "fails clearly when Homebrew is unavailable" do
    _stdout, stderr, status = Open3.capture3(
      { "PATH" => "/usr/bin:/bin" },
      File.join(ROOT, "script", "install"),
      "--help",
    )

    expect(status).not_to be_success
    expect(stderr).to include("Homebrew is not installed")
  end

  it "scopes vulnerability scans to the Brewfile and preserves scanner exit codes" do
    bin = File.join(@root, "bin")
    log = File.join(@root, "brew-args")
    FileUtils.mkdir_p(bin)
    write("bin/brew", <<~'SH')
      #!/usr/bin/env bash
      if [[ "$1" == "command" && "$2" == "vulns" ]]; then
        exit 0
      fi
      printf '%s\n' "$@" > "$BREW_ARGS_LOG"
      exit "$VULNS_EXIT"
    SH
    FileUtils.chmod("u+x", File.join(bin, "brew"))

    _stdout, stderr, status = Open3.capture3(
      {
        "PATH" => "#{bin}:#{ENV.fetch("PATH")}",
        "BREW_ARGS_LOG" => log,
        "VULNS_EXIT" => "1"
      },
      File.join(ROOT, "script", "vulns"),
    )

    expect(status.exitstatus).to eq(1)
    expect(File.readlines(log, chomp: true)).to eq([
                                                     "vulns", "--brewfile", File.join(ROOT, "Brewfile"), "--deps", "--severity", "high"
                                                   ])
    expect(stderr).to include("Skipped packages", "coverage gap", "cask checksums")
  end

  it "fails with status 2 when brew-vulns is not installed" do
    bin = File.join(@root, "bin")
    FileUtils.mkdir_p(bin)
    write("bin/brew", <<~SH)
      #!/usr/bin/env bash
      exit 1
    SH
    FileUtils.chmod("u+x", File.join(bin, "brew"))

    _stdout, stderr, status = Open3.capture3(
      { "PATH" => "#{bin}:#{ENV.fetch("PATH")}" },
      File.join(ROOT, "script", "vulns"),
    )

    expect(status.exitstatus).to eq(2)
    expect(stderr).to include("brew vulns is not installed")
  end
end
