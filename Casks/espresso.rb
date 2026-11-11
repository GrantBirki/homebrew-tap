cask "espresso" do
  version "0.2.0"
  sha256 "5e2b848467918487b42b91622ebbaebbedb649a5b7908f667e1f423fd5179702"

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
