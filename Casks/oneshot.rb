cask "oneshot" do
  version "1.0.0"
  sha256 "77f1cf3bdd044a624f603eda4ea61e01e7fb7f7722ff50c36f8b98ad884c4a49"

  url "https://github.com/grantbirki/oneshot/releases/download/v#{version}/OneShot.zip"
  name "OneShot"
  desc "Open source screenshot utility for macOS"
  homepage "https://github.com/grantbirki/oneshot"

  depends_on macos: ">= :tahoe"

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
