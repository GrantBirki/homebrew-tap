cask "oneshot" do
  version "1.2.11"
  sha256 "d7dd0db92d458f69ea2d285a6c27fd7f2b0afedf8c1a8d94d8b91e5e9fd92782"

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
