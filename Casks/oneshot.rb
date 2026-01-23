cask "oneshot" do
  version "0.1.0"
  sha256 "6c699508cd2174b8f5b3731da81664616cb0000cf0fb037391279c1d904300eb"

  url "https://github.com/grantbirki/oneshot/releases/download/v#{version}/OneShot.zip"
  name "OneShot"
  desc "Open source screenshot utility for macOS"
  homepage "https://github.com/grantbirki/oneshot"

  depends_on macos: ">= :sonoma"

  livecheck do
    url :url
    strategy :github_latest
  end

  app "OneShot.app"

  postflight do
    result = system_command(
      "/usr/bin/xattr",
      args: ["-dr", "com.apple.quarantine", "#{appdir}/OneShot.app"],
      print_stderr: true,
    )
    unless result.success?
      opoo "Failed to clear quarantine automatically. You can run: `xattr -dr com.apple.quarantine #{appdir}/OneShot.app`"
    end
  end

  zap trash: [
    "~/Library/Preferences/com.grantbirki.oneshot.plist",
    "~/Library/Saved Application State/com.grantbirki.oneshot.savedState",
  ]
end
