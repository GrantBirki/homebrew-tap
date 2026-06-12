# frozen_string_literal: true

require "json"

module HomebrewTap
  ReceiptStatus = Struct.new(:entry, :state, :source_tap, :installed_version, :path, :error, keyword_init: true) do
    def tap
      source_tap
    end

    def wrong_tap?
      state == :wrong_tap
    end
  end

  class ReceiptScanner
    attr_reader :prefix

    def initialize(prefix:)
      @prefix = prefix
    end

    def classify(entry)
      path = receipt_path(entry)
      return ReceiptStatus.new(entry: entry, state: :missing) unless path

      data = JSON.parse(File.read(path))
      return unknown(entry, path, "receipt root is not an object") unless data.is_a?(Hash)

      source = data["source"]
      return unknown(entry, path, "receipt source is not an object") unless source.is_a?(Hash)

      tap = source["tap"]
      return unknown(entry, path, "receipt source.tap is missing") unless present_string?(tap)

      version = installed_version(entry, source, path)
      return unknown(entry, path, "receipt source version is missing") unless present_string?(version)

      ReceiptStatus.new(
        entry: entry,
        state: receipt_state(tap),
        source_tap: tap,
        installed_version: version,
        path: path
      )
    rescue JSON::ParserError, Errno::ENOENT => e
      ReceiptStatus.new(entry: entry, state: :unknown_receipt, path: path, error: e.message)
    end

    private

    def receipt_path(entry)
      case entry.type
      when :brew
        Dir[File.join(prefix, "Cellar", entry.token, "*", "INSTALL_RECEIPT.json")].max
      when :cask
        cask_receipts(entry).max_by { |path| [File.mtime(path), path] }
      end
    end

    def receipt_state(tap)
      tap == TAP_NAME ? :tap_managed : :wrong_tap
    end

    def installed_version(entry, source, path)
      version = entry.type == :brew ? version_from_path(entry, path) : source["version"]
      return version if present_string?(version)

      version_from_path(entry, path)
    end

    def version_from_path(entry, path)
      return File.basename(File.dirname(path)) if entry.type == :brew

      match = path.match(%r{/\.metadata/([^/]+)/})
      match&.[](1)
    end

    def present_string?(value)
      value.is_a?(String) && !value.empty?
    end

    def unknown(entry, path, error)
      ReceiptStatus.new(entry: entry, state: :unknown_receipt, path: path, error: error)
    end

    def cask_receipts(entry)
      metadata = File.join(prefix, "Caskroom", entry.token, ".metadata")
      direct = File.join(metadata, "INSTALL_RECEIPT.json")
      nested = File.join(metadata, "*", "*", "INSTALL_RECEIPT.json")
      ([direct] + Dir[nested]).select { |path| File.file?(path) }
    end
  end
end
