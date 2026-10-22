# frozen_string_literal: true

require "spec_helper"
require "rbconfig"
require_relative "../../lib/homebrew_tap/ncat_trust"

RSpec.shared_context "stock Ncat CA fixture" do
  before do
    @stock = "stock public CA bundle\n"
    @bundle = Pathname(write("keg/share/ncat/ca-bundle.crt", @stock))
    @ca = Pathname(write("etc/ca-certificates/cert.pem", "corrected roots and custom local CA\n"))
    @backup_dir = Pathname(@root) / "var/ncat-ca-backups"
    stub_const("HomebrewTap::NcatTrust::STOCK_SHA256", Digest::SHA256.hexdigest(@stock))
  end

  def repairer(**)
    HomebrewTap::NcatTrust.new(
      bundle: @bundle, ca_file: @ca, ca_version: "2026-10-20", backup_dir: @backup_dir, **
    )
  end

  def backup_path
    @backup_dir / "ca-bundle-#{Digest::SHA256.hexdigest(@stock)}.crt"
  end
end

RSpec.describe HomebrewTap::NcatTrust do
  include_context "stock Ncat CA fixture"

  it "defaults to a non-mutating plan" do
    expect(repairer.repair.status).to eq(:planned)
    expect(@bundle.read).to eq(@stock)
    expect(@bundle).not_to be_symlink
    expect(@backup_dir).not_to exist
    expect(@bundle.dirname.children).to eq([@bundle])
  end

  it "backs up the stock file before atomically installing the link and preserves local CAs" do
    allow(File).to receive(:rename).and_wrap_original do |rename, source, destination|
      expect(Pathname(source)).to be_symlink
      expect(@bundle).not_to be_symlink
      expect(@bundle.read).to eq(@stock)
      expect(backup_path.read).to eq(@stock)
      rename.call(source, destination)
    end

    result = repairer.repair(dry_run: false)

    expect(result.status).to eq(:repaired)
    expect(result.backup).to eq(backup_path)
    expect(backup_path.stat.mode & 0o777).to eq(0o600)
    expect(@bundle.readlink).to eq(@ca)
    expect(@bundle.read).to include("custom local CA")
    expect(@bundle.dirname.children).to eq([@bundle])
  end

  it "is idempotent for the exact intended link" do
    repairer.repair(dry_run: false)
    before = @bundle.lstat

    expect(repairer.repair(dry_run: false).status).to eq(:unchanged)
    expect(@bundle.lstat.ino).to eq(before.ino)
    expect(backup_path.read).to eq(@stock)
  end

  it "accepts a later corrected CA formula revision" do
    expect(repairer(ca_version: "2026-10-21_1").repair.status).to eq(:planned)
  end

  it "refuses old, missing, and unrecognized CA formula versions" do
    ["2026-10-19", nil, "latest"].each do |version|
      expect { repairer(ca_version: version).repair(dry_run: false) }.to raise_error(HomebrewTap::Error, /2026-10-20 or newer/)
    end
    expect(@bundle.read).to eq(@stock)
    expect(@backup_dir).not_to exist
  end

  it "refuses an invalid calendar date" do
    expect { repairer(ca_version: "2026-99-99").repair }.to raise_error(HomebrewTap::Error, /version is invalid/)
  end

  it "refuses a missing corrected bundle" do
    @ca.unlink
    expect { repairer.repair(dry_run: false) }.to raise_error(HomebrewTap::Error, /missing, empty, or unreadable/)
    expect(@bundle.read).to eq(@stock)
  end

  it "refuses an empty corrected bundle" do
    @ca.write("")
    expect { repairer.repair }.to raise_error(HomebrewTap::Error, /missing, empty, or unreadable/)
  end

  it "refuses an unreadable corrected bundle" do
    allow_any_instance_of(Pathname).to receive(:readable?).and_return(false)
    expect { repairer.repair }.to raise_error(HomebrewTap::Error, /missing, empty, or unreadable/)
  end

  it "refuses a custom bundle without replacing or backing it up" do
    @bundle.write("custom CA additions\n")
    expect { repairer.repair(dry_run: false) }.to raise_error(HomebrewTap::Error, /custom Ncat CA file/)
    expect(@bundle.read).to eq("custom CA additions\n")
    expect(@backup_dir).not_to exist
  end

  it "refuses another symlink without following its target" do
    custom = Pathname(write("custom.pem", "custom roots\n"))
    @bundle.unlink
    @bundle.make_symlink(custom)

    expect { repairer.repair(dry_run: false) }.to raise_error(HomebrewTap::Error, /unexpected Ncat CA symlink/)
    expect(@bundle.readlink).to eq(custom)
    expect(custom.read).to eq("custom roots\n")
  end

  it "refuses a non-regular original file" do
    @bundle.unlink
    @bundle.mkdir
    expect { repairer.repair(dry_run: false) }.to raise_error(HomebrewTap::Error, /non-regular CA file/)
  end

  it "reports a missing original bundle without creating anything" do
    @bundle.unlink
    expect { repairer.repair(dry_run: false) }.to raise_error(HomebrewTap::Error, /Ncat CA repair failed/)
    expect(@backup_dir).not_to exist
  end

  it "refuses a replacement that aliases the original bundle" do
    expect { repairer(ca_file: @bundle).repair(dry_run: false) }.to raise_error(HomebrewTap::Error, /different files/)
  end

  it "reuses only an existing exact stock backup" do
    FileUtils.mkdir_p(@backup_dir)
    backup_path.write(@stock)
    before = backup_path.stat

    expect(repairer.repair(dry_run: false).backup).to eq(backup_path)
    expect(backup_path.stat.ino).to eq(before.ino)
  end

  it "refuses a modified backup without replacing either file" do
    FileUtils.mkdir_p(@backup_dir)
    backup_path.write("keep this backup\n")
    expect { repairer.repair(dry_run: false) }.to raise_error(HomebrewTap::Error, /backup does not match/)
    expect(@bundle.read).to eq(@stock)
    expect(backup_path.read).to eq("keep this backup\n")
  end

  it "refuses a symlink at the backup path" do
    FileUtils.mkdir_p(@backup_dir)
    backup_path.make_symlink(@bundle)
    expect { repairer.repair(dry_run: false) }.to raise_error(HomebrewTap::Error, /non-regular CA file/)
    expect(@bundle).not_to be_symlink
    expect(backup_path).to be_symlink
  end

  it "detects replacement between lstat and open without overwriting new contents" do
    allow(File).to receive(:open).and_wrap_original do |open, path, *args, &block|
      @bundle.write("changed before open\n") if Pathname(path) == @bundle
      open.call(path, *args, &block)
    end

    expect { repairer.repair(dry_run: false) }.to raise_error(HomebrewTap::Error, /changed before reading/)
    expect(@bundle.read).to eq("changed before open\n")
  end

  it "detects changes during a read" do
    allow(File).to receive(:open).and_wrap_original do |open, path, *args, &block|
      open.call(path, *args) do |file|
        if Pathname(path) == @bundle
          allow(file).to receive(:read).and_wrap_original do |read|
            data = read.call
            @bundle.write("changed while reading\n")
            data
          end
        end
        block.call(file)
      end
    end

    expect { repairer.repair(dry_run: false) }.to raise_error(HomebrewTap::Error, /changed while reading/)
    expect(@bundle.read).to eq("changed while reading\n")
  end

  it "detects a changed inode even when replacement bytes match stock" do
    allow(File).to receive(:symlink).and_wrap_original do |symlink, source, destination|
      symlink.call(source, destination)
      replacement = @bundle.dirname / "replacement.crt"
      replacement.write(@stock)
      File.rename(replacement, @bundle)
    end

    expect { repairer.repair(dry_run: false) }.to raise_error(HomebrewTap::Error, /changed before replacement/)
    expect(@bundle).not_to be_symlink
    expect(@bundle.read).to eq(@stock)
    expect(@bundle.dirname.children).to eq([@bundle])
  end

  it "preserves custom contents changed immediately before replacement" do
    allow(File).to receive(:symlink).and_wrap_original do |symlink, source, destination|
      symlink.call(source, destination)
      @bundle.write("new custom roots\n")
    end

    expect { repairer.repair(dry_run: false) }.to raise_error(HomebrewTap::Error, /changed before replacement/)
    expect(@bundle.read).to eq("new custom roots\n")
    expect(@bundle.dirname.children).to eq([@bundle])
    expect(backup_path.read).to eq(@stock)
  end

  it "cleans up its temporary link if atomic replacement fails" do
    allow(File).to receive(:rename).and_raise(Errno::EACCES)
    expect { repairer.repair(dry_run: false) }.to raise_error(HomebrewTap::Error, /Ncat CA repair failed/)
    expect(@bundle.read).to eq(@stock)
    expect(@bundle.dirname.children).to eq([@bundle])
  end

  it "does not remove an unrelated entry when the temporary name collides" do
    allow(SecureRandom).to receive(:hex).and_return("collision")
    collision = @bundle.dirname / ".ncat-ca-collision"
    collision.write("unrelated\n")
    expect { repairer.repair(dry_run: false) }.to raise_error(HomebrewTap::Error, /Ncat CA repair failed/)
    expect(collision.read).to eq("unrelated\n")
    expect(@bundle.read).to eq(@stock)
  end
end

RSpec.describe HomebrewTap::NcatTrustCommand do
  include_context "stock Ncat CA fixture"

  def command(argv)
    nmap = Struct.new(:any_installed_prefix).new(@bundle.dirname.parent.parent)
    ca = Struct.new(:pkgetc, :any_installed_version).new(@ca.dirname, "2026-10-20")
    @loader = ->(name) { { "grantbirki/tap/nmap" => nmap, "ca-certificates" => ca }.fetch(name) }
    @out = StringIO.new
    @err = StringIO.new
    described_class.new(argv: argv, formula_loader: @loader, backup_dir: @backup_dir, out: @out, err: @err)
  end

  it "shows help without loading formulae" do
    instance = command(["--help"])
    expect(@loader).not_to receive(:call)
    expect(instance.run).to eq(0)
    expect(@out.string).to include("--dry-run | --apply")
    expect(command(["-h"]).run).to eq(0)
  end

  it "rejects unknown and conflicting options without mutation" do
    [["--unknown"], ["--apply", "--dry-run"]].each do |argv|
      expect(command(argv).run).to eq(2)
    end
    expect(@bundle).not_to be_symlink
  end

  it "plans by default and with the explicit dry-run flag" do
    [[], ["--dry-run"]].each do |argv|
      expect(command(argv).run).to eq(0)
      expect(@out.string).to include("Would replace")
    end
    expect(@backup_dir).not_to exist
    expect(@bundle).not_to be_symlink
  end

  it "applies only with the explicit flag and reports its backup" do
    expect(command(["--apply"]).run).to eq(0)
    expect(@out.string).to include("Ncat now uses", "Stock bundle backup:")
    expect(@bundle.readlink).to eq(@ca)
    expect(command(["--apply"]).run).to eq(0)
    expect(@out.string).to include("already uses")
  end

  it "refuses to install a missing Nmap" do
    instance = command(["--apply"])
    allow(@loader).to receive(:call).with("grantbirki/tap/nmap").and_return(Struct.new(:any_installed_prefix).new(nil))
    expect(instance.run).to eq(1)
    expect(@err.string).to include("Nmap is not installed")
    expect(@backup_dir).not_to exist
  end

  it "reports guarded repair failures" do
    @bundle.write("custom roots\n")
    expect(command(["--apply"]).run).to eq(1)
    expect(@err.string).to include("custom Ncat CA file")
    expect(@bundle.read).to eq("custom roots\n")
  end
end

RSpec.describe "Ncat trust entrypoint" do
  include_context "stock Ncat CA fixture"

  def run_entrypoint(argument)
    bin = File.join(@root, "bin")
    bootstrap = write("fake-homebrew.rb", <<~RUBY)
      require "pathname"
      HOMEBREW_PREFIX = Pathname(ENV.fetch("TEST_BREW_PREFIX"))
      $LOAD_PATH.unshift(File.join(ENV.fetch("TEST_BREW_PREFIX"), "fake-lib"))
      require File.join(ENV.fetch("TEST_TAP_ROOT"), "lib/homebrew_tap/ncat_trust")
      HomebrewTap::NcatTrust.send(:remove_const, :STOCK_SHA256)
      HomebrewTap::NcatTrust.const_set(:STOCK_SHA256, Digest::SHA256.hexdigest("stock public CA bundle\\n"))
    RUBY
    write("fake-lib/formulary.rb", <<~RUBY)
      raise "API launch override leaked" if ENV.key?("HOMEBREW_NO_INSTALL_FROM_API")
      module Formula
        def self.[](name)
          prefix = Pathname(ENV.fetch("TEST_BREW_PREFIX"))
          return Struct.new(:any_installed_prefix).new(prefix / "keg") if name == "grantbirki/tap/nmap"
          return Struct.new(:pkgetc, :any_installed_version).new(prefix / "etc/ca-certificates", "2026-10-20") if name == "ca-certificates"

          raise "Unexpected formula request"
        end
      end
    RUBY
    write("bin/brew", <<~SH)
      #!/usr/bin/env bash
      set -euo pipefail
      test "$1" = "ruby"
      test "$2" = "-e"
      test "$HOMEBREW_NO_AUTO_UPDATE" = "1"
      test "$HOMEBREW_REQUIRE_TAP_TRUST" = "1"
      shift
      exec "#{RbConfig.ruby}" -r "#{bootstrap}" "$@"
    SH
    FileUtils.chmod("u+x", File.join(bin, "brew"))
    Open3.capture3(
      { "PATH" => "#{bin}:#{ENV.fetch("PATH")}", "TEST_BREW_PREFIX" => @root, "TEST_TAP_ROOT" => ROOT },
      File.join(ROOT, "script", "ncat-trust"), argument,
    )
  end

  it "uses only supported brew ruby options and forwards help" do
    stdout, stderr, status = run_entrypoint("--help")
    expect(status).to be_success, stderr
    expect(stdout).to include("Usage: script/ncat-trust")
    expect(stderr).to be_empty
    expect(@backup_dir).not_to exist
  end

  it "routes an explicit dry run without modifying the installed-file fixture" do
    stdout, stderr, status = run_entrypoint("--dry-run")
    expect(status).to be_success, stderr
    expect(stdout).to include("Would replace")
    expect(@bundle).not_to be_symlink
    expect(Pathname(@root) / "var/homebrew-tap/ncat-ca-backups").not_to exist
  end

  it "routes an apply only to the fixture paths resolved by Homebrew" do
    stdout, stderr, status = run_entrypoint("--apply")
    expect(status).to be_success, stderr
    expect(stdout).to include("Ncat now uses", "Stock bundle backup:")
    expect(@bundle.readlink).to eq(@ca)
    expect(Pathname(@root) / "var/homebrew-tap/ncat-ca-backups").to be_directory
  end

  it "fails clearly if Homebrew is absent" do
    _stdout, stderr, status = Open3.capture3(
      { "PATH" => "/usr/bin:/bin" }, File.join(ROOT, "script", "ncat-trust"), "--help"
    )
    expect(status.exitstatus).to eq(1)
    expect(stderr).to include("Homebrew is required")
  end
end
