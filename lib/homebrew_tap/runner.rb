# frozen_string_literal: true

require "open3"

module HomebrewTap
  CommandResult = Struct.new(:cmd, :stdout, :stderr, :status, keyword_init: true) do
    def success?
      status.zero?
    end
  end

  class Runner
    attr_reader :out

    def initialize(out: $stdout)
      @out = out
    end

    def run(*cmd)
      out.puts command_line(cmd)
      success = system(*cmd)
      CommandResult.new(cmd: cmd, stdout: "", stderr: "", status: success ? 0 : 1)
    end

    def run!(*cmd)
      result = run(*cmd)
      raise Error, "command failed: #{command_line(cmd)}" unless result.success?

      result
    end

    def capture(*cmd, allow_failure: false)
      stdout, stderr, status = Open3.capture3(*cmd)
      if !status.success? && !allow_failure
        raise Error, "command failed: #{command_line(cmd)}\n#{stderr}"
      end

      stdout
    end

    def command_available?(name)
      ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |directory|
        path = File.join(directory, name)
        File.file?(path) && File.executable?(path)
      end
    end

    private

    def command_line(cmd)
      "$ #{cmd.join(" ")}"
    end
  end
end
