cask "espresso" do
  version "0.1.3"
  sha256 "1931cbb3abdba4377a54dc90fcf45382ca81fadd42037095081d1959f0b098ff"

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
