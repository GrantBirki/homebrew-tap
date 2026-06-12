cask "shit" do
  version "0.2.0"
  sha256 "e568efd850c75986db8ce7c341bf275e670b4b9d18a54025ffa89f30c604e7c5"

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
