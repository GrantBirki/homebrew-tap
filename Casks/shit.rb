cask "shit" do
  version "0.1.1"
  sha256 "38a583abfb64de172ab3f74a26049cbef1a8472a3cd313716fe8ac4d80f77f72"

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
