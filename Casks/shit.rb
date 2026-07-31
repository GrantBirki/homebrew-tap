cask "shit" do
  version "0.2.6"
  sha256 "e58b371cc5bf69b3ecc35df761a35a8dcc796f395cb6fd9f958479078777ef7d"

  url "https://github.com/grantbirki/shit/releases/download/v#{version}/Shit.zip"
  name "Shit"
  desc "Menu bar app that makes missed meetings harder"
  homepage "https://github.com/grantbirki/shit"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :tahoe

  app "Shit.app"

  zap trash: [
    "~/Library/Preferences/io.birki.shit.plist",
    "~/Library/Saved Application State/io.birki.shit.savedState",
  ]
end
