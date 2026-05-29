# frozen_string_literal: true

module HomebrewTap
  class LintCommand
    USAGE = "Usage: script/lint [--help]"

    def initialize(argv:, runner: Runner.new, out: $stdout, err: $stderr, root: ROOT)
      @argv = argv.dup
      @runner = runner
      @out = out
      @err = err
      @root = root
    end

    def run
      return help(0) if @argv.delete("--help") || @argv.delete("-h")
      return unknown unless @argv.empty?

      ui = UI.new(out: @out, err: @err)
      ui.step("Ruby syntax")
      TestChecks::RubySyntax.new(root: @root, runner: @runner, quiet: true).validate
      ui.success("Ruby syntax")
      ui.step("GitHub Actions pins")
      TestChecks::WorkflowPins.new(root: @root).validate
      ui.success("GitHub Actions pins")
      ui.step("Homebrew style")
      TestChecks::HomebrewStyle.new(root: @root, runner: @runner, quiet: true).validate
      ui.success("Homebrew style")
      ui.step("RuboCop")
      TestChecks::RuboCop.new(root: @root, runner: @runner, quiet: true).validate
      ui.success("RuboCop")
      ui.success("Lint complete.")
      0
    rescue Error => e
      @err.puts e.message
      1
    end

    private

    def help(status)
      @out.puts USAGE
      status
    end

    def unknown
      @err.puts "Unknown option: #{@argv.first}"
      @out.puts USAGE
      2
    end
  end

  class TestCommand
    USAGE = "Usage: script/test [--help] [--skip-rspec]"

    def initialize(argv:, runner: Runner.new, out: $stdout, err: $stderr, root: ROOT)
      @argv = argv.dup
      @runner = runner
      @out = out
      @err = err
      @root = root
      @skip_rspec = false
    end

    def run
      parse_args!
      return help(0) if @help

      TestChecks::BundlerSupplyChain.new(root: @root).validate
      TestChecks::WorkflowPins.new(root: @root).validate
      TestChecks::RubySyntax.new(root: @root, runner: @runner).validate
      TestChecks::CaskParsing.new(root: @root, runner: @runner).validate
      TestChecks::BrewfileParsing.new(root: @root, runner: @runner).validate
      TestChecks::BrewfilePins.new(root: @root).validate
      @runner.run!("bundle", "exec", "rspec", "spec") unless @skip_rspec
      @out.puts "Test complete."
      0
    rescue Error => e
      @err.puts e.message
      1
    end

    private

    def parse_args!
      until @argv.empty?
        case (arg = @argv.shift)
        when "--help", "-h" then @help = true
        when "--skip-rspec" then @skip_rspec = true
        else
          @err.puts "Unknown option: #{arg}"
          raise SystemExit, 2
        end
      end
    end

    def help(status)
      @out.puts USAGE
      status
    end
  end
end
