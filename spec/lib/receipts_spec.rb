# frozen_string_literal: true

require "spec_helper"

RSpec.describe HomebrewTap::ReceiptScanner do
  def entry(type, token)
    HomebrewTap::BrewfileEntry.new(type: type, token: token, full_name: "grantbirki/tap/#{token}")
  end

  it "classifies missing, tap-managed, wrong-tap, and unknown receipts" do
    prefix = File.join(@root, "brew")
    receipt(
      prefix,
      :brew,
      "bash",
      body: { "source" => { "tap" => "grantbirki/tap", "versions" => { "stable" => "0.9.0" } } }
    )
    receipt(
      prefix,
      :cask,
      "alacritty",
      body: { "source" => { "tap" => "homebrew/cask", "version" => "0.16.1" } }
    )
    receipt(prefix, :brew, "bat", body: { "source" => {} })
    receipt(prefix, :brew, "tree", body: "{nope")

    scanner = described_class.new(prefix: prefix)

    expect(scanner.classify(entry(:brew, "missing")).state).to eq(:missing)
    managed = scanner.classify(entry(:brew, "bash"))
    expect(managed.state).to eq(:tap_managed)
    expect(managed.installed_version).to eq("1.0.0")
    wrong = scanner.classify(entry(:cask, "alacritty"))
    expect(wrong.state).to eq(:wrong_tap)
    expect(wrong).to be_wrong_tap
    expect(wrong.tap).to eq("homebrew/cask")
    expect(wrong.installed_version).to eq("0.16.1")
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
    expect(status.installed_version).to eq("3.0.4")
    expect(status.path).to eq(path)
  end

  it "uses the newest cask receipt when direct and nested metadata both exist" do
    prefix = File.join(@root, "brew")
    direct = receipt(
      prefix,
      :cask,
      "keepassxc",
      body: { "source" => { "tap" => "homebrew/cask", "version" => "2.7.11" } }
    )
    nested = File.join(prefix, "Caskroom", "keepassxc", ".metadata", "2.7.12", "20260529010101.123", "INSTALL_RECEIPT.json")
    FileUtils.mkdir_p(File.dirname(nested))
    File.write(nested, JSON.generate("source" => { "tap" => "grantbirki/tap" }))
    File.utime(Time.now - 60, Time.now - 60, direct)
    File.utime(Time.now, Time.now, nested)

    status = described_class.new(prefix: prefix).classify(entry(:cask, "keepassxc"))

    expect(status.state).to eq(:tap_managed)
    expect(status.path).to eq(nested)
  end

  it "fails closed for malformed receipt shapes and missing cask versions" do
    prefix = File.join(@root, "brew")
    receipt(prefix, :brew, "scalar", body: "[]")
    receipt(prefix, :brew, "source", body: { "source" => "homebrew/core" })
    receipt(prefix, :cask, "tap", body: { "source" => {} })
    receipt(prefix, :cask, "version", body: { "source" => { "tap" => "homebrew/cask" } })

    scanner = described_class.new(prefix: prefix)

    expect(scanner.classify(entry(:brew, "scalar")).error).to eq("receipt root is not an object")
    expect(scanner.classify(entry(:brew, "source")).error).to eq("receipt source is not an object")
    expect(scanner.classify(entry(:cask, "tap")).error).to eq("receipt source.tap is missing")
    expect(scanner.classify(entry(:cask, "version")).error).to eq("receipt source version is missing")
  end
end
