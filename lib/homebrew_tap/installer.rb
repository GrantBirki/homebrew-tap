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

    attr_reader :argv, :runner, :out, :err, :repo_root, :brewfile_path

    def initialize(argv:, runner: Runner.new, out: $stdout, err: $stderr, repo_root: ROOT)
      @argv = argv.dup
      @runner = runner
      @out = out
      @err = err
      @repo_root = repo_root
      @brewfile_path = File.join(repo_root, "Brewfile")
      @dry_run = false
      @repoint = true
      @update = true
    end

    def run
      parse_args!
      return help(0) if @help

      validate!
      out.puts "Using Brewfile: #{brewfile_path}"
      tap!
      update!
      TapCheckout.new(runner: runner, repo_root: repo_root, out: out).with_current_checkout(dry_run: dry_run?) do
        repoint!
        bundle_install!
      end
      out.puts "Install complete."
      0
    rescue Error => e
      err.puts e.message
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
        out.puts "would tap #{TAP_NAME} from #{repo_root}"
        return
      end

      result = runner.run("brew", "tap", TAP_NAME, repo_root)
      runner.run!("brew", "tap", TAP_NAME) unless result.success?
    end

    def update!
      if !@update
        out.puts "Skipping brew update."
      elsif dry_run?
        out.puts "would run: brew update"
      else
        runner.run!("brew", "update")
      end
    end

    def repoint!
      entries = Brewfile.new(path: brewfile_path).tap_entries
      prefix = runner.capture("brew", "--prefix").strip
      scanner = ReceiptScanner.new(prefix: prefix)

      entries.each do |entry|
        status = scanner.classify(entry)
        report_status(status)
        next unless status.wrong_tap?

        if @repoint
          reinstall(entry)
        else
          out.puts "skipping repoint for #{entry.full_name}"
        end
      end
    end

    def report_status(status)
      case status.state
      when :missing
        out.puts "missing #{status.entry.type}: #{status.entry.full_name}"
      when :tap_managed
        out.puts "already tap-managed #{status.entry.type}: #{status.entry.full_name}"
      when :wrong_tap
        out.puts "wrong tap #{status.entry.type}: #{status.entry.full_name} is from #{status.tap}"
      when :unknown_receipt
        out.puts "unknown receipt #{status.entry.type}: #{status.entry.full_name}"
      end
    end

    def reinstall(entry)
      flag = entry.type == :brew ? "--formula" : "--cask"
      if dry_run?
        out.puts "would run: brew reinstall #{flag} #{entry.full_name}"
      else
        runner.run!("brew", "reinstall", flag, entry.full_name)
      end
    end

    def bundle_install!
      if dry_run?
        out.puts "would run: brew bundle install --file=#{brewfile_path}"
      else
        runner.run!("brew", "bundle", "install", "--file=#{brewfile_path}")
      end
    end
  end
end
