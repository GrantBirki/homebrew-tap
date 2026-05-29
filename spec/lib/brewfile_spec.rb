# frozen_string_literal: true

require "spec_helper"

RSpec.describe HomebrewTap::Brewfile do
  it "parses only grantbirki tap formulae and casks" do
    path = write("Brewfile", <<~BREWFILE)
      tap "grantbirki/tap"
      brew "grantbirki/tap/bash"
      brew "gh"
      cask "grantbirki/tap/alacritty" # pinned terminal
      cask "visual-studio-code"
      cask "alacritty", full_name: "grantbirki/tap/alacritty"
    BREWFILE

    entries = described_class.new(path: path).tap_entries

    expect(entries.map(&:type)).to eq(%i[brew cask cask])
    expect(entries.map(&:token)).to eq(%w[bash alacritty alacritty])
    expect(entries.map(&:full_name)).to all(start_with("grantbirki/tap/"))
  end
end
