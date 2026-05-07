cask "espresso" do
  version "0.1.1"
  sha256 "25ee16c0b9eab824749278473be9d7478ae2b08d4d8863c29ffa71cdf2d7e7c9"

  url "https://github.com/grantbirki/espresso/releases/download/v#{version}/Espresso.zip"
  name "Espresso"
  desc "Menu bar app that keeps your Mac awake"
  homepage "https://github.com/grantbirki/espresso"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :tahoe"

  app "Espresso.app"

  postflight do
    result = system_command(
      "/usr/bin/xattr",
      args:         ["-dr", "com.apple.quarantine", "#{appdir}/Espresso.app"],
      print_stderr: true,
    )
    unless result.success?
      opoo "Failed to clear quarantine automatically. " \
           "You can run: `xattr -dr com.apple.quarantine #{appdir}/Espresso.app`"
    end
  end

  zap trash: [
    "~/Library/Preferences/io.birki.espresso.plist",
    "~/Library/Saved Application State/io.birki.espresso.savedState",
  ]
end
