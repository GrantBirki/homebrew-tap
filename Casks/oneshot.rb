cask "oneshot" do
  version "1.1.0"
  sha256 "c5f0baba9f68fb382c0f1e4a19b09eb9b1b116f4fd98efc834556d161d94bf84"

  url "https://github.com/grantbirki/oneshot/releases/download/v#{version}/OneShot.zip"
  name "OneShot"
  desc "Open source screenshot utility"
  homepage "https://github.com/grantbirki/oneshot"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :tahoe"

  app "OneShot.app"

  postflight do
    result = system_command(
      "/usr/bin/xattr",
      args:         ["-dr", "com.apple.quarantine", "#{appdir}/OneShot.app"],
      print_stderr: true,
    )
    unless result.success?
      opoo "Failed to clear quarantine automatically. " \
           "You can run: `xattr -dr com.apple.quarantine #{appdir}/OneShot.app`"
    end
  end

  zap trash: [
    "~/Library/Preferences/com.grantbirki.oneshot.plist",
    "~/Library/Saved Application State/com.grantbirki.oneshot.savedState",
  ]
end
