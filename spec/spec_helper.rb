# frozen_string_literal: true

require "coverage"

ROOT = File.expand_path("..", __dir__)
COVERAGE_TARGETS = (
  Dir[File.join(ROOT, "lib/homebrew_tap*.rb")] +
  Dir[File.join(ROOT, "lib/homebrew_tap/*.rb")] +
  %w[script/install script/lint script/test script/vendor].map { |path| File.join(ROOT, path) }
).map { |path| File.realpath(path) }.freeze

Coverage.start(lines: true)

require "fileutils"
require "json"
require "stringio"
require "tmpdir"

require "rspec"

require_relative "../lib/homebrew_tap"
require_relative "../lib/homebrew_tap/brewfile"
require_relative "../lib/homebrew_tap/ui"
require_relative "../lib/homebrew_tap/runner"
require_relative "../lib/homebrew_tap/receipts"
require_relative "../lib/homebrew_tap/tap_checkout"
require_relative "../lib/homebrew_tap/installer"
require_relative "../lib/homebrew_tap/vendor"
require_relative "../lib/homebrew_tap/test_checks"
require_relative "../lib/homebrew_tap/commands"

SCRIPT_COVERAGE = {}

class FakeRunner
  attr_reader :commands

  def initialize(captures: {}, failures: [], available: true)
    @captures = captures.transform_keys { |key| Array(key) }
    @failures = failures.map { |key| Array(key) }
    @available = available
    @commands = []
  end

  def run(*cmd)
    @commands << cmd
    HomebrewTap::CommandResult.new(cmd: cmd, stdout: "", stderr: "", status: @failures.include?(cmd) ? 1 : 0)
  end

  def run!(*cmd)
    result = run(*cmd)
    raise HomebrewTap::Error, "command failed: #{cmd.join(" ")}" unless result.success?

    result
  end

  def run_quiet!(*cmd)
    run!(*cmd)
  end

  def capture(*cmd, allow_failure: false)
    value = @captures.fetch(cmd) do
      return "" if allow_failure

      raise HomebrewTap::Error, "missing capture: #{cmd.join(" ")}"
    end
    value.is_a?(Array) ? value.shift.to_s : value.to_s
  end

  def command_available?(_name)
    @available
  end
end

module FixtureHelpers
  def write(path, content)
    full_path = File.join(@root, path)
    FileUtils.mkdir_p(File.dirname(full_path))
    File.write(full_path, content)
    full_path
  end

  def receipt(prefix, type, token, version: "1.0.0", body:)
    path =
      if type == :brew
        File.join(prefix, "Cellar", token, version, "INSTALL_RECEIPT.json")
      else
        File.join(prefix, "Caskroom", token, ".metadata", "INSTALL_RECEIPT.json")
      end
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body.is_a?(String) ? body : JSON.generate(body))
    path
  end

  def run_script(path, argv = [])
    original_argv = ARGV.dup
    original_stdout = $stdout
    original_stderr = $stderr
    stdout = StringIO.new
    stderr = StringIO.new
    status = 0

    ARGV.replace(argv)
    $stdout = stdout
    $stderr = stderr
    begin
      load path
    rescue SystemExit => e
      status = e.status
    ensure
      record_script_coverage(path)
      ARGV.replace(original_argv)
      $stdout = original_stdout
      $stderr = original_stderr
    end

    { status: status, stdout: stdout.string, stderr: stderr.string }
  end

  def record_script_coverage(path)
    target = File.realpath(path)
    Coverage.peek_result.each do |coverage_path, data|
      next unless File.realpath(coverage_path) == target

      lines = data.is_a?(Hash) ? data.fetch(:lines) : data
      aggregate = SCRIPT_COVERAGE[target] ||= []
      lines.each_with_index do |count, index|
        next if count.nil?

        aggregate[index] = aggregate[index].to_i + count
      end
    rescue Errno::ENOENT
      next
    end
  end
end

RSpec.configure do |config|
  config.include FixtureHelpers
  config.disable_monkey_patching!
  config.expect_with(:rspec) { |expectations| expectations.syntax = :expect }
  config.mock_with(:rspec) { |mocks| mocks.verify_partial_doubles = true }

  config.around do |example|
    Dir.mktmpdir do |root|
      @root = root
      example.run
    end
  end

  config.after(:suite) do
    result = Coverage.result
    coverage_by_path = result.to_h do |path, data|
      [File.realpath(path), data.is_a?(Hash) ? data.fetch(:lines) : data]
    rescue Errno::ENOENT
      [File.expand_path(path), data.is_a?(Hash) ? data.fetch(:lines) : data]
    end
    SCRIPT_COVERAGE.each { |path, lines| coverage_by_path[path] = lines }

    uncovered = []
    COVERAGE_TARGETS.each do |path|
      lines = coverage_by_path[path]
      unless lines
        uncovered << "#{path}: not loaded by specs"
        next
      end

      File.readlines(path).each_with_index do |_source, index|
        count = lines[index]
        next if count.nil? || count.positive?

        uncovered << "#{path}:#{index + 1}"
      end
    end

    next if uncovered.empty?

    warn "\nRuby line coverage is below 100%:"
    warn uncovered.join("\n")
    exit 1
  end
end
