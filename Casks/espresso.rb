cask "espresso" do
  version "0.1.2"
  sha256 "a1bdc059e50c255922a201fe65b0ac5105d979604aa3b5248d2502c93b53213e"

  url "https://github.com/grantbirki/espresso/releases/download/v#{version}/Espresso.zip"
  name "Espresso"
  desc "Menu bar app that prevents system sleep"
  homepage "https://github.com/grantbirki/espresso"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on arch: :arm64
  depends_on macos: :tahoe

  app "Espresso.app"

  zap trash: [
    "~/Library/Preferences/io.birki.espresso.plist",
    "~/Library/Saved Application State/io.birki.espresso.savedState",
  ]
end
