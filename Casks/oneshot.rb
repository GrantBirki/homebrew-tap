cask "oneshot" do
  version "1.2.10"
  sha256 "2dafa4d9565e15885735c9d01a55da9c56923a04e5ccc76682215ba04511cad4"

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
