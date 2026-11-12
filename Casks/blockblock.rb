cask "blockblock" do
  version "2.5.2"
  sha256 "7e5a332a4da6a22e8b494418c3cac241d24b43176c8bfc4bb2ef8bdc640bd4c7"

  url "https://github.com/objective-see/BlockBlock/releases/download/v#{version}/BlockBlock_#{version}.zip",
      verified: "github.com/objective-see/BlockBlock/"
  name "BlockBlock"
  desc "Monitors common persistence locations"
  homepage "https://objective-see.org/products/blockblock.html"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on :macos

  installer script: {
    executable: "/usr/bin/env",
    args:       [
      "-i", "PATH=/usr/bin:/bin:/usr/sbin:/sbin", "/bin/bash", "-c",
      <<~BASH,
        set -euo pipefail
        work=$(mktemp -d /private/tmp/blockblock-bootstrap.XXXXXX)
        trap 'rm -rf "$work"' EXIT
        ditto "$1" "$work/install-blockblock.sh"
        [[ -f $work/install-blockblock.sh && ! -L $work/install-blockblock.sh ]] || exit 1
        chown root:wheel "$work/install-blockblock.sh"
        chmod 700 "$work/install-blockblock.sh"
        actual=$(shasum -a 256 "$work/install-blockblock.sh")
        [[ ${actual%% *} == "e9979b47433693c8df6d650ae79b5182c0ad289bb7ae094ea7396878cb11fccc" ]] || { echo 'BlockBlock installer helper checksum mismatch.' >&2; exit 1; }
        /bin/bash "$work/install-blockblock.sh" "$2"
      BASH
      "blockblock-install", "#{__dir__}/../libexec/install-blockblock.sh", "#{staged_path}/BlockBlock Installer.app",
    ],
    sudo:       true,
  }

  uninstall script: {
    executable: "#{staged_path}/BlockBlock Installer.app/Contents/MacOS/BlockBlock Installer",
    args:       ["-uninstall"],
    sudo:       true,
  }

  zap trash: [
    "~/Library/Caches/com.objective-see.blockblock.helper",
    "~/Library/HTTPStorages/com.objective-see.blockblock.helper",
    "~/Library/Preferences/com.objective-see.blockblock.helper.plist",
    "~/Library/Preferences/com.objectiveSee.BlockBlock.plist",
  ]

  caveats <<~EOS
    Approve the normal macOS Open prompts for BlockBlock and BlockBlock Helper.
    Grant BlockBlock Full Disk Access in System Settings to enable monitoring.
  EOS
end
