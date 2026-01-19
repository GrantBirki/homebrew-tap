cask "oneshot" do
  version "0.0.2"
  sha256 "551ec4ce37d145788abf105d8a0f7564983ebe98d792d490318387afdfa83771"

  url "https://github.com/grantbirki/oneshot/releases/download/v#{version}/OneShot.zip"
  name "OneShot"
  desc "Open source screenshot utility for macOS"
  homepage "https://github.com/grantbirki/oneshot"

  app "OneShot.app"

  zap trash: [
    "~/Library/Preferences/com.grantbirki.oneshot.plist",
    "~/Library/Saved Application State/com.grantbirki.oneshot.savedState",
  ]
end
