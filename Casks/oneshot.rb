cask "oneshot" do
  version "1.2.9"
  sha256 "9b35936fc745931196aae2940127f6c5f66dcdd6ba3b62838042934d17cd86ae"

  url "https://github.com/grantbirki/oneshot/releases/download/v#{version}/OneShot.zip"
  name "OneShot"
  desc "Open source screenshot utility"
  homepage "https://github.com/grantbirki/oneshot"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on arch: :arm64
  depends_on macos: :tahoe

  app "OneShot.app"

  zap trash: [
    "~/Library/Preferences/com.grantbirki.oneshot.plist",
    "~/Library/Saved Application State/com.grantbirki.oneshot.savedState",
  ]
end
