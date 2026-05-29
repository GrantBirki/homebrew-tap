# frozen_string_literal: true

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
    end

    def run
      parse_args!
      return help(0) if @help

      validate!
      ui.step("Using Brewfile: #{brewfile_path}")
      tap!
      update!
      TapCheckout.new(runner: runner, repo_root: repo_root, ui: ui).with_current_checkout(dry_run: dry_run?) do
        repoint!
        bundle_install!
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

      result = runner.run("brew", "tap", TAP_NAME, repo_root)
      runner.run!("brew", "tap", TAP_NAME) unless result.success?
    end

    def update!
      if !@update
        ui.skip("Skipping brew update")
      elsif dry_run?
        ui.dry_run("brew update")
      else
        ui.step("Updating Homebrew")
        runner.run!("brew", "update")
      end
    end

    def repoint!
      entries = Brewfile.new(path: brewfile_path).tap_entries
      if entries.empty?
        ui.skip("No #{TAP_NAME} Brewfile entries to inspect")
        return
      end

      ui.step("Inspecting #{entries.length} tap-qualified Brewfile entries")
      prefix = runner.capture("brew", "--prefix").strip
      scanner = ReceiptScanner.new(prefix: prefix)

      entries.each do |entry|
        status = scanner.classify(entry)
        report_status(status)
        next unless status.wrong_tap?

        if @repoint
          reinstall(entry)
        else
          ui.skip("Skipping repoint for #{entry.full_name}")
        end
      end
    end

    def report_status(status)
      @status_counts[status.state] += 1
      case status.state
      when :missing
        ui.warning("#{entry_label(status.entry)} is not installed")
      when :tap_managed
        ui.success("#{entry_label(status.entry)} is already managed by #{TAP_NAME}")
      when :wrong_tap
        ui.warning("#{entry_label(status.entry)} needs repoint from #{status.tap}")
      when :unknown_receipt
        ui.warning("#{entry_label(status.entry)} has an unknown receipt source")
      end
    end

    def reinstall(entry)
      flag = entry.type == :brew ? "--formula" : "--cask"
      if dry_run?
        ui.dry_run("brew reinstall #{flag} #{entry.full_name}")
      else
        ui.step("Repointing #{entry_label(entry)}")
        runner.run!("brew", "reinstall", flag, entry.full_name)
      end
    end

    def bundle_install!
      if dry_run?
        ui.dry_run("brew bundle install --file=#{brewfile_path}")
      else
        ui.step("Installing Brewfile packages")
        runner.run!("brew", "bundle", "install", "--file=#{brewfile_path}")
      end
    end

    def entry_label(entry)
      "#{entry.type} #{entry.full_name}"
    end

    def summary
      STATUS_ORDER.map do |state|
        count = @status_counts[state]
        "#{count} #{STATUS_LABELS.fetch(state)}" if count.positive?
      end.compact.join(", ")
    end
  end
end
