# frozen_string_literal: true

require "date"
require "digest"
require "fileutils"
require "pathname"
require "securerandom"
require_relative "../homebrew_tap"

module HomebrewTap
  class NcatTrust
    STOCK_SHA256 = "099733ca62e3a7009701e68bf2de0ce6c19075c1371795e0d2f911b2d1ead7ba"
    MIN_CA_VERSION = "2026-10-20"
    Result = Struct.new(:status, :backup, keyword_init: true)

    def initialize(bundle:, ca_file:, ca_version:, backup_dir:)
      @bundle = Pathname(bundle).expand_path
      @ca_file = Pathname(ca_file).expand_path
      @ca_version = ca_version.to_s
      @backup_dir = Pathname(backup_dir).expand_path
    end

    def repair(dry_run: true)
      validate_ca!
      if @bundle.symlink?
        raise Error, "Refusing an unexpected Ncat CA symlink: #{@bundle}" unless @bundle.readlink.to_s == @ca_file.to_s

        return Result.new(status: :unchanged)
      end

      data, identity = read_regular_file(@bundle)
      raise Error, "Refusing to replace a custom Ncat CA file: #{@bundle}" unless Digest::SHA256.hexdigest(data) == STOCK_SHA256
      raise Error, "Ncat CA file and replacement must be different files" if File.identical?(@bundle, @ca_file)

      return Result.new(status: :planned) if dry_run

      backup = back_up(data)
      replace_bundle(identity)
      Result.new(status: :repaired, backup: backup)
    rescue SystemCallError, IOError => e
      raise Error, "Ncat CA repair failed: #{e.message}"
    end

    private

    def validate_ca!
      version = @ca_version.sub(/_\d+\z/, "")
      unless version.match?(/\A\d{4}-\d{2}-\d{2}\z/) && Date.iso8601(version) >= Date.iso8601(MIN_CA_VERSION)
        raise Error, "Installed ca-certificates #{MIN_CA_VERSION} or newer is required"
      end
      unless @ca_file.file? && @ca_file.readable? && @ca_file.size.positive?
        raise Error, "Corrected Homebrew CA file is missing, empty, or unreadable: #{@ca_file}"
      end
    rescue Date::Error
      raise Error, "Installed ca-certificates version is invalid: #{@ca_version}"
    end

    def file_identity(stat)
      [stat.dev, stat.ino, stat.mode, stat.size, stat.mtime, stat.ctime]
    end

    def read_regular_file(path)
      before = path.lstat
      raise Error, "Refusing a non-regular CA file: #{path}" unless before.file?

      File.open(path, File::RDONLY | File::NOFOLLOW) do |file|
        identity = file_identity(file.stat)
        raise Error, "CA file changed before reading: #{path}" unless file_identity(before) == identity

        data = file.read
        raise Error, "CA file changed while reading: #{path}" unless file_identity(file.stat) == identity

        [data, identity]
      end
    end

    def back_up(data)
      FileUtils.mkdir_p(@backup_dir)
      backup = @backup_dir / "ca-bundle-#{STOCK_SHA256}.crt"
      if backup.exist? || backup.symlink?
        saved, = read_regular_file(backup)
        raise Error, "Existing Ncat CA backup does not match the stock bundle: #{backup}" unless Digest::SHA256.hexdigest(saved) == STOCK_SHA256
      else
        File.open(backup, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
          file.write(data)
          file.flush
          file.fsync
        end
      end
      backup
    end

    def replace_bundle(identity)
      temporary = @bundle.dirname / ".ncat-ca-#{SecureRandom.hex(12)}"
      created = false
      begin
        File.symlink(@ca_file, temporary)
        created = true
        current, current_identity = read_regular_file(@bundle)
        unless identity == current_identity && Digest::SHA256.hexdigest(current) == STOCK_SHA256
          raise Error, "Ncat CA file changed before replacement: #{@bundle}"
        end

        File.rename(temporary, @bundle)
      ensure
        temporary.unlink if created && temporary.symlink? && temporary.readlink.to_s == @ca_file.to_s
      end
    end
  end

  class NcatTrustCommand
    USAGE = "Usage: script/ncat-trust [--dry-run | --apply] [--help]"
    MESSAGES = {
      planned: "Would replace the stock Ncat CA bundle with the corrected Homebrew CA file.",
      unchanged: "Ncat already uses the corrected Homebrew CA file.",
      repaired: "Ncat now uses the corrected Homebrew CA file."
    }.freeze

    def initialize(argv:, formula_loader:, backup_dir:, out: $stdout, err: $stderr)
      @argv = argv.dup
      @formula_loader = formula_loader
      @backup_dir = backup_dir
      @out = out
      @err = err
    end

    def run
      return usage(0) if @argv.delete("--help") || @argv.delete("-h")

      apply = @argv.delete("--apply")
      dry_run = @argv.delete("--dry-run")
      return usage(2) unless @argv.empty? && !(apply && dry_run)

      nmap = @formula_loader.call("#{TAP_NAME}/nmap")
      prefix = nmap.any_installed_prefix
      raise Error, "Nmap is not installed; no package will be installed automatically" unless prefix

      ca = @formula_loader.call("ca-certificates")
      result = NcatTrust.new(
        bundle: Pathname(prefix) / "share/ncat/ca-bundle.crt", ca_file: ca.pkgetc / "cert.pem",
        ca_version: ca.any_installed_version, backup_dir: @backup_dir
      ).repair(dry_run: !apply)
      @out.puts MESSAGES.fetch(result.status)
      @out.puts "Stock bundle backup: #{result.backup}" if result.backup
      0
    rescue Error => e
      @err.puts e.message
      1
    end

    private

    def usage(status)
      @out.puts USAGE
      status
    end
  end
end
