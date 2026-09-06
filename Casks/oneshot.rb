cask "oneshot" do
  version "1.2.12"
  sha256 "7818d61530ed0dfabff8c78b1c91fb00da6e5ac0b698b5c069db874d603c784c"

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
