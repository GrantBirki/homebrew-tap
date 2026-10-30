cask "keepassxc" do
  arch arm: "arm64", intel: "x86_64"

  version "2.8.0,2.8.0-1"
  sha256 arm:   "85f0e75e258ef513f0fc7f5bf470cad0943b7d7e8191b2171f9898ad32e62b9c",
         intel: "28492c5535570020179150b2871b3c54abd032cbb8cdee2f1b3fa7c46cdba43e"

  url "https://github.com/keepassxreboot/keepassxc/releases/download/#{version.csv.first}/KeePassXC-#{version.csv.second || version.csv.first}-#{arch}.dmg",
      verified: "github.com/keepassxreboot/keepassxc/"
  name "KeePassXC"
  desc "Password manager app"
  homepage "https://keepassxc.org/"

  # The release tag and rebuilt macOS asset can have different versions.
  livecheck do
    url :url
    regex(%r{/v?(\d+(?:\.\d+)+)/KeePassXC[._-]v?(\d+(?:[.-]\d+)+)[._-]#{arch}\.dmg$}i)
    strategy :github_latest do |json, regex|
      json["assets"]&.map do |asset|
        match = asset["browser_download_url"]&.match(regex)
        next if match.blank?

        next match[1] if match[1] == match[2]

        "#{match[1]},#{match[2]}"
      end
    end
  end

  conflicts_with cask: [
    "keepassxc@beta",
    "keepassxc@snapshot",
  ]
  depends_on macos: :monterey

  app "KeePassXC.app"
  binary "#{appdir}/KeePassXC.app/Contents/MacOS/keepassxc-cli"
  manpage "#{appdir}/KeePassXC.app/Contents/Resources/man/man1/keepassxc.1"
  manpage "#{appdir}/KeePassXC.app/Contents/Resources/man/man1/keepassxc-cli.1"

  uninstall quit: "org.keepassxc.keepassxc"

  zap trash: [
    "~/.keepassxc",
    "~/Library/Application Support/CrashReporter/KeePassXC_*.plist",
    "~/Library/Application Support/keepassxc",
    "~/Library/Caches/org.keepassx.keepassxc",
    "~/Library/Logs/DiagnosticReports/KeePassXC_*.crash",
    "~/Library/Preferences/keepassxc.keepassxc.plist",
    "~/Library/Preferences/org.keepassx.keepassxc.plist",
    "~/Library/Saved Application State/org.keepassx.keepassxc.savedState",
  ]
end
