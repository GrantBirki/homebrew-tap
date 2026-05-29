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

  it "finds versioned cask metadata receipts" do
    prefix = File.join(@root, "brew")
    path = File.join(prefix, "Caskroom", "secretive", ".metadata", "3.0.4", "20260529010101.123", "INSTALL_RECEIPT.json")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, JSON.generate("source" => { "tap" => "homebrew/cask" }))

    status = described_class.new(prefix: prefix).classify(entry(:cask, "secretive"))

    expect(status.state).to eq(:wrong_tap)
    expect(status.tap).to eq("homebrew/cask")
    expect(status.path).to eq(path)
  end

  it "uses the newest cask receipt when direct and nested metadata both exist" do
    prefix = File.join(@root, "brew")
    direct = receipt(prefix, :cask, "keepassxc", body: { "source" => { "tap" => "homebrew/cask" } })
    nested = File.join(prefix, "Caskroom", "keepassxc", ".metadata", "2.7.12", "20260529010101.123", "INSTALL_RECEIPT.json")
    FileUtils.mkdir_p(File.dirname(nested))
    File.write(nested, JSON.generate("source" => { "tap" => "grantbirki/tap" }))
    File.utime(Time.now - 60, Time.now - 60, direct)
    File.utime(Time.now, Time.now, nested)

    status = described_class.new(prefix: prefix).classify(entry(:cask, "keepassxc"))

    expect(status.state).to eq(:tap_managed)
    expect(status.path).to eq(nested)
  end
end
