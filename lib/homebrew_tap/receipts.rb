# frozen_string_literal: true

require "json"

module HomebrewTap
  ReceiptStatus = Struct.new(:entry, :state, :tap, :path, :error, keyword_init: true) do
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
      tap = data.dig("source", "tap")
      state = tap.nil? ? :unknown_receipt : (tap == TAP_NAME ? :tap_managed : :wrong_tap)
      ReceiptStatus.new(entry: entry, state: state, tap: tap, path: path)
    rescue JSON::ParserError => e
      ReceiptStatus.new(entry: entry, state: :unknown_receipt, path: path, error: e.message)
    end

    private

    def receipt_path(entry)
      case entry.type
      when :brew
        Dir[File.join(prefix, "Cellar", entry.token, "*", "INSTALL_RECEIPT.json")].sort.last
      when :cask
        path = File.join(prefix, "Caskroom", entry.token, ".metadata", "INSTALL_RECEIPT.json")
        File.exist?(path) ? path : nil
      end
    end
  end
end
