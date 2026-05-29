# frozen_string_literal: true

module HomebrewTap
  class Vendor
    USAGE = <<~USAGE
      Usage: script/vendor [--dry-run]

      Refreshes the committed RubyGems lockfile checksums and vendor/cache.
      This is the intentional networked RubyGems refresh path.
    USAGE

    COMMANDS = [
      ["bundle", "lock", "--add-checksums"],
      ["bundle", "cache", "--all", "--all-platforms", "--no-install"]
    ].freeze

    attr_reader :argv, :runner, :out, :err

    def initialize(argv:, runner: Runner.new, out: $stdout, err: $stderr)
      @argv = argv.dup
      @runner = runner
      @out = out
      @err = err
      @dry_run = false
    end

    def run
      parse_args!
      return help(0) if @help

      out.puts "Refreshing vendored Ruby dependencies..."
      COMMANDS.each { |cmd| run_command(cmd) }
      out.puts "Vendored Ruby dependencies are refreshed."
      0
    rescue Error => e
      err.puts e.message
      1
    end

    private

    def parse_args!
      until argv.empty?
        case (arg = argv.shift)
        when "--dry-run", "-n" then @dry_run = true
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

    def run_command(cmd)
      if @dry_run
        out.puts "would run: #{cmd.join(" ")}"
      else
        runner.run!(*cmd)
      end
    end
  end
end
