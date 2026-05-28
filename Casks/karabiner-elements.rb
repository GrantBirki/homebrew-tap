cask "karabiner-elements" do
  version "16.0.0"
  sha256 "b960f731890a74231c229e5453c4ee7109efb328c4fb63aed8974e347fd1f9c0"

  url "https://github.com/pqrs-org/Karabiner-Elements/releases/download/v#{version}/Karabiner-Elements-#{version}.dmg",
      verified: "github.com/pqrs-org/Karabiner-Elements/"
  name "Karabiner Elements"
  desc "Keyboard customiser"
  homepage "https://karabiner-elements.pqrs.org/"

  livecheck do
    skip "Pinned version for bootstrap reproducibility"
  end

  auto_updates true
  depends_on macos: :ventura

  pkg "Karabiner-Elements.pkg"
  binary "/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli"

  uninstall early_script: {
              executable: "/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/scripts/uninstall/remove_files.sh",
              sudo:       true,
            },
            launchctl:    [
              "org.pqrs.karabiner.agent.karabiner_grabber",
              "org.pqrs.karabiner.agent.karabiner_observer",
              "org.pqrs.karabiner.karabiner_console_user_server",
              "org.pqrs.karabiner.karabiner_grabber",
              "org.pqrs.karabiner.karabiner_observer",
              "org.pqrs.karabiner.karabiner_session_monitor",
              "org.pqrs.karabiner.NotificationWindow",
            ],
            signal:       [
              ["TERM", "org.pqrs.Karabiner-Menu"],
              ["TERM", "org.pqrs.Karabiner-NotificationWindow"],
            ],
            script:       {
              executable: "/Library/Application Support/org.pqrs/Karabiner-Elements/uninstall_core.sh",
              sudo:       true,
            },
            pkgutil:      [
              "org.pqrs.Karabiner-DriverKit-VirtualHIDDevice",
              "org.pqrs.Karabiner-Elements",
            ],
            delete:       "/Library/Application Support/org.pqrs"

  # The system extension 'org.pqrs.Karabiner-DriverKit-VirtualHIDDevice*' should not be uninstalled by Cask.

  zap trash: [
    "~/.config/karabiner",
    "~/.local/share/karabiner",
    "~/Library/Application Scripts/org.pqrs.Karabiner-VirtualHIDDevice-Manager",
    "~/Library/Application Support/Karabiner-Elements",
    "~/Library/Caches/org.pqrs.Karabiner-Elements.Updater",
    "~/Library/Containers/org.pqrs.Karabiner-VirtualHIDDevice-Manager",
    "~/Library/HTTPStorages/org.pqrs.Karabiner-Elements.Settings",
    "~/Library/Preferences/org.pqrs.Karabiner-Elements.Updater.plist",
  ]
end
