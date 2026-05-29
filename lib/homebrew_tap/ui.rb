# frozen_string_literal: true

require "shellwords"

module HomebrewTap
  class UI
    COLORS = {
      blue: "\e[0;34m",
      green: "\e[0;32m",
      purple: "\e[0;35m",
      red: "\e[0;31m",
      yellow: "\e[0;33m",
      reset: "\e[0m"
    }.freeze

    def self.color_enabled?(out)
      ENV["NO_COLOR"].nil? && out.respond_to?(:tty?) && out.tty?
    end

    def initialize(out:, err: $stderr, color: nil)
      @out = out
      @err = err
      @color = color.nil? ? self.class.color_enabled?(out) : color
    end

    def step(message)
      write(@out, :blue, "🍺 #{message}")
    end

    def success(message)
      write(@out, :green, "✅ #{message}")
    end

    def info(message)
      write(@out, :blue, "ℹ️  #{message}")
    end

    def warning(message)
      write(@out, :yellow, "⚠️  #{message}")
    end

    def skip(message)
      write(@out, :yellow, "⏭️  #{message}")
    end

    def dry_run(message)
      write(@out, :purple, "📝 would run: #{message}")
    end

    def command(cmd)
      write(@out, :purple, "  $ #{cmd.map { |arg| display_arg(arg) }.join(" ")}")
    end

    def error(message)
      write(@err, :red, "❌ #{message}")
    end

    private

    def write(stream, color, message)
      stream.puts paint(color, message)
    end

    def paint(color, message)
      return message unless @color

      "#{COLORS.fetch(color)}#{message}#{COLORS.fetch(:reset)}"
    end

    def display_arg(arg)
      value = arg.to_s
      value = "#{value.lines.first.chomp} ..." if value.include?("\n")
      Shellwords.escape(value)
    end
  end
end
