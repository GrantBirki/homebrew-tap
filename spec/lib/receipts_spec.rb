# frozen_string_literal: true

require "spec_helper"

RSpec.describe HomebrewTap::ReceiptScanner do
  def entry(type, token)
    HomebrewTap::BrewfileEntry.new(type: type, token: token, full_name: "grantbirki/tap/#{token}")
  end

  it "classifies missing, tap-managed, wrong-tap, and unknown receipts" do
    prefix = File.join(@root, "brew")
    receipt(prefix, :brew, "bash", body: { "source" => { "tap" => "grantbirki/tap" } })
    receipt(prefix, :cask, "alacritty", body: { "source" => { "tap" => "homebrew/cask" } })
    receipt(prefix, :brew, "bat", body: { "source" => {} })
    receipt(prefix, :brew, "tree", body: "{nope")

    scanner = described_class.new(prefix: prefix)

    expect(scanner.classify(entry(:brew, "missing")).state).to eq(:missing)
    expect(scanner.classify(entry(:brew, "bash")).state).to eq(:tap_managed)
    wrong = scanner.classify(entry(:cask, "alacritty"))
    expect(wrong.state).to eq(:wrong_tap)
    expect(wrong).to be_wrong_tap
    expect(wrong.tap).to eq("homebrew/cask")
    expect(scanner.classify(entry(:brew, "bat")).state).to eq(:unknown_receipt)
    unknown = scanner.classify(entry(:brew, "tree"))
    expect(unknown.state).to eq(:unknown_receipt)
    expect(unknown.error).to be_a(String)
    expect(unknown.error).not_to be_empty
  end
end
