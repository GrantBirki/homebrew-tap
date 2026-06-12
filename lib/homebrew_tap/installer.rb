# frozen_string_literal: true

require "rubygems/version"

module HomebrewTap
  class Installer
    USAGE = <<~USAGE
      Usage: script/install [options]

      Installs packages from Brewfile and repoints already-installed tap-qualified
      formulae/casks to grantbirki/tap by default.

      Options:
        --dry-run      Print planned actions without changing Homebrew state
        --no-repoint   Do not reinstall packages currently sourced from another tap
        --no-update    Skip brew update
        --help         Show this help

      Note: cask repointing uses brew reinstall and may trigger uninstall/install
      hooks, sudo prompts, or application restarts.
    USAGE

    HOMEBREW_ENV = { "HOMEBREW_REQUIRE_TAP_TRUST" => "1" }.freeze
    UPDATE_ENV = HOMEBREW_ENV.merge("HOMEBREW_UPDATE_TO_TAG" => "1").freeze
    MIN_HOMEBREW_MAJOR = 6
    PRIVILEGED_CASKS = %w[blockblock karabiner-elements osquery santa].freeze
    STATUS_ORDER = %i[tap_managed wrong_tap missing unknown_receipt].freeze
    STATUS_LABELS = {
      tap_managed: "tap-managed",
      wrong_tap: "wrong-tap",
      missing: "missing",
      unknown_receipt: "unknown-receipt"
    }.freeze

    attr_reader :argv, :runner, :out, :err, :repo_root, :brewfile_path, :ui

    def initialize(argv:, runner: Runner.new, out: $stdout, err: $stderr, repo_root: ROOT, ui: nil)
      @argv = argv.dup
      @runner = runner
      @out = out
      @err = err
      @ui = ui || UI.new(out: out, err: err)
      @repo_root = repo_root
      @brewfile_path = File.join(repo_root, "Brewfile")
      @dry_run = false
      @repoint = true
      @update = true
      @status_counts = Hash.new(0)
      @target_versions = {}
    end

    def run
      parse_args!
      return help(0) if @help

      validate!
      ui.step("Using Brewfile: #{brewfile_path}")
      entries = Brewfile.new(path: brewfile_path).tap_entries
      @target_versions = entries.to_h { |entry| [entry.full_name, target_version(entry)] }
      statuses = inspect_entries(entries)
      ensure_known_receipts!(statuses)

      update!
      validate_homebrew_version!
      tap!
      TapCheckout.new(runner: runner, repo_root: repo_root, ui: ui).with_current_checkout(dry_run: dry_run?) do
        bundle_install!
        statuses = scan(entries) unless dry_run?
        ensure_known_receipts!(statuses)
        repoint!(entries, statuses)
        statuses = scan(entries) unless dry_run?
        verify_final_receipts!(statuses)
        update_status_counts(statuses)
      end
      ui.success("Install complete")
      ui.info("Repoint summary: #{summary}") unless @status_counts.empty?
      0
    rescue Error => e
      ui.error(e.message)
      1
    end

    private

    def dry_run?
      @dry_run
    end

    def parse_args!
      until argv.empty?
        case (arg = argv.shift)
        when "--dry-run" then @dry_run = true
        when "--no-repoint" then @repoint = false
        when "--no-update" then @update = false
        when "--help", "-h" then @help = true
        else
          err.puts "Unknown option: #{arg}"
          return help(2)
        end
      end
    end

    def help(status)
      out.puts USAGE
      raise SystemExit, status if status != 0

      status
    end

    def validate!
      raise Error, "Homebrew is not installed. See https://brew.sh/ to install it first." unless runner.command_available?("brew")
      raise Error, "Brewfile not found at #{brewfile_path}." unless File.file?(brewfile_path)
    end

    def update!
      if !@update
        ui.skip("Skipping brew update")
      elsif dry_run?
        ui.dry_run("HOMEBREW_UPDATE_TO_TAG=1 brew update")
      else
        ui.step("Updating Homebrew to a stable tag")
        runner.run!(UPDATE_ENV, "brew", "update")
      end
    end

    def validate_homebrew_version!
      output = runner.capture("brew", "--version")
      major = output[/\AHomebrew\s+(\d+)/, 1]&.to_i
      return if major && major >= MIN_HOMEBREW_MAJOR

      found = output.lines.first.to_s.strip
      raise Error, "Homebrew #{MIN_HOMEBREW_MAJOR} or newer is required; found #{found.empty? ? "an unknown version" : found}."
    end

    def tap!
      if dry_run?
        ui.dry_run("brew tap #{TAP_NAME} #{repo_root} if missing")
        return
      end

      ui.step("Ensuring #{TAP_NAME} is tapped")
      tap_path = runner.capture("brew", "--repo", TAP_NAME, allow_failure: true).strip
      if !tap_path.empty? && File.directory?(tap_path)
        ui.success("#{TAP_NAME} already tapped at #{tap_path}")
        return
      end

      result = runner.run(HOMEBREW_ENV, "brew", "tap", TAP_NAME, repo_root)
      runner.run!(HOMEBREW_ENV, "brew", "tap", TAP_NAME) unless result.success?
    end

    def inspect_entries(entries)
      if entries.empty?
        ui.skip("No #{TAP_NAME} Brewfile entries to inspect")
        return []
      end

      ui.step("Inspecting #{entries.length} tap-qualified Brewfile entries")
      scan(entries).each { |status| report_status(status) }
    end

    def scan(entries)
      return [] if entries.empty?

      prefix = runner.capture("brew", "--prefix").strip
      scanner = ReceiptScanner.new(prefix: prefix)
      entries.map { |entry| scanner.classify(entry) }
    end

    def ensure_known_receipts!(statuses)
      unknown = statuses.select { |status| status.state == :unknown_receipt }
      return if unknown.empty?

      details = unknown.map do |status|
        "#{entry_label(status.entry)} at #{status.path || "unknown path"}: #{status.error || "unknown receipt format"}"
      end
      raise Error, "Refusing to change Homebrew state because receipt provenance is unknown:\n#{details.join("\n")}"
    end

    def repoint!(entries, statuses)
      if entries.empty?
        ui.skip("No #{TAP_NAME} Brewfile entries to repoint")
        return
      end

      statuses.each do |status|
        next unless status.wrong_tap?

        if @repoint
          reinstall(status.entry)
        else
          ui.skip("Skipping repoint for #{status.entry.full_name}")
        end
      end
    end

    def report_status(status)
      target = "#{TAP_NAME} #{target_version_for(status.entry)}"
      markers = status_markers(status)
      case status.state
      when :missing
        ui.warning("#{entry_label(status.entry)}: not installed -> #{target}#{markers}")
      when :tap_managed
        ui.success("#{entry_label(status.entry)}: #{status.tap} #{status.installed_version} -> #{target}#{markers}")
      when :wrong_tap
        ui.warning("#{entry_label(status.entry)}: #{status.tap} #{status.installed_version} -> #{target}#{markers}")
      when :unknown_receipt
        ui.warning("#{entry_label(status.entry)} has an unknown receipt: #{status.error}")
      end
    end

    def status_markers(status)
      markers = []
      markers << "PRIVILEGED" if privileged_cask?(status.entry)
      markers << "DOWNGRADE" if downgrade?(status.installed_version, target_version_for(status.entry))
      markers.empty? ? "" : " #{markers.map { |marker| "[#{marker}]" }.join(" ")}"
    end

    def privileged_cask?(entry)
      entry.type == :cask && PRIVILEGED_CASKS.include?(entry.token)
    end

    def downgrade?(installed, target)
      return false unless installed && target

      Gem::Version.new(normalize_version(installed)) > Gem::Version.new(normalize_version(target))
    rescue ArgumentError
      false
    end

    def normalize_version(version)
      version.to_s.tr("_", ".")
    end

    def reinstall(entry)
      flag = entry.type == :brew ? "--formula" : "--cask"
      if dry_run?
        ui.dry_run("brew reinstall #{flag} #{entry.full_name}")
      else
        ui.step("Repointing #{entry_label(entry)}")
        runner.run!(HOMEBREW_ENV, "brew", "reinstall", flag, entry.full_name)
      end
    end

    def bundle_install!
      if dry_run?
        ui.dry_run("brew bundle install --file=#{brewfile_path}")
      else
        ui.step("Installing Brewfile packages and establishing item trust")
        runner.run!(HOMEBREW_ENV, "brew", "bundle", "install", "--file=#{brewfile_path}")
      end
    end

    def verify_final_receipts!(statuses)
      ensure_known_receipts!(statuses)
      return if dry_run?
      return unless @repoint

      wrong = statuses.select(&:wrong_tap?)
      return if wrong.empty?

      details = wrong.map do |status|
        "#{entry_label(status.entry)} is still sourced from #{status.tap} #{status.installed_version}"
      end
      raise Error, "Repoint validation failed:\n#{details.join("\n")}"
    end

    def update_status_counts(statuses)
      @status_counts = Hash.new(0)
      statuses.each { |status| @status_counts[status.state] += 1 }
    end

    def target_version(entry)
      source = File.read(package_path(entry))
      version = entry.type == :cask ? cask_version(source) : formula_version(source)
      return version if version

      raise Error, "Could not determine the target version for #{entry.full_name}."
    rescue Errno::ENOENT
      raise Error, "Package definition not found for #{entry.full_name}."
    end

    def package_path(entry)
      directory = entry.type == :brew ? "Formula" : "Casks"
      File.join(repo_root, directory, "#{entry.token}.rb")
    end

    def cask_version(source)
      source.scan(/^\s+version\s+["']([^"']+)["']/).flatten.last
    end

    def formula_version(source)
      version = source[/^\s+version\s+["']([^"']+)["']/, 1]
      version ||= source[/^\s+tag:\s+["']([^"']+)["']/, 1]
      version ||= version_from_formula_url(source)
      revision = source[/^  revision\s+(\d+)/, 1]
      revision && revision != "0" ? "#{version}_#{revision}" : version
    end

    def version_from_formula_url(source)
      url = source[/^  url\s+["']([^"']+)["']/, 1]
      return unless url

      filename = url.split("?").first.split("/").last
      filename.scan(/\d+(?:\.\d+)+/).last
    end

    def target_version_for(entry)
      @target_versions.fetch(entry.full_name)
    end

    def entry_label(entry)
      "#{entry.type} #{entry.token}"
    end

    def summary
      STATUS_ORDER.map do |state|
        count = @status_counts[state]
        "#{count} #{STATUS_LABELS.fetch(state)}" if count.positive?
      end.compact.join(", ")
    end
  end
end
