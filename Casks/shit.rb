cask "shit" do
  version "0.2.7"
  sha256 "a0e68822801705480fd191b2e3baf97b8598c216cf7ce35f24bcf20c8640fb3e"

  url "https://github.com/grantbirki/shit/releases/download/v#{version}/Shit.zip"
  name "Shit"
  desc "Menu bar app that makes missed meetings harder"
  homepage "https://github.com/grantbirki/shit"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on arch: :arm64
  depends_on macos: :tahoe

  app "Shit.app"

  zap trash: [
    "~/Library/Preferences/io.birki.shit.plist",
    "~/Library/Saved Application State/io.birki.shit.savedState",
  ]
end
