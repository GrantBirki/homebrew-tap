# frozen_string_literal: true

module HomebrewTap
  BrewfileEntry = Struct.new(:type, :token, :full_name, keyword_init: true)

  class Brewfile
    attr_reader :path

    def initialize(path:)
      @path = path
    end

    def tap_entries
      File.readlines(path).filter_map { |line| parse_tap_entry(line) }
    end

    private

    def parse_tap_entry(line)
      stripped = line.sub(/\s+#.*\z/, "").strip
      match = stripped.match(/\A(?<type>brew|cask)\s+["']#{Regexp.escape(TAP_NAME)}\/(?<token>[^"']+)["']/)
      return entry(match) if match

      match = stripped.match(
        /\A(?<type>brew|cask)\s+["'][^"']+["'].*full_name:\s*["']#{Regexp.escape(TAP_NAME)}\/(?<token>[^"']+)["']/
      )
      entry(match) if match
    end

    def entry(match)
      return unless match

      BrewfileEntry.new(type: match[:type].to_sym, token: match[:token], full_name: "#{TAP_NAME}/#{match[:token]}")
    end
  end
end
