# BlockBlock installation

Install `grantbirki/tap/blockblock` from a logged-in macOS desktop session. Approve the normal macOS **Open** prompts for BlockBlock and BlockBlock Helper, then grant **BlockBlock** Full Disk Access in System Settings. A running daemon alone does not mean monitoring is active before that permission is granted.

The [2.5.2 upstream install script](https://github.com/objective-see/BlockBlock/blob/9d53e2230633a5a692bd82717c678c50ca98f30c/Installer/Source/Script/configure.sh) clears quarantine. This tap installs the unchanged signed daemon and helper with a local helper instead. The cask pins that helper's SHA-256 and verifies a private root-owned copy before running it in a clean environment. The helper verifies the exact installer signatures, signed resources and Gatekeeper acceptance, preserves quarantine on every copied path, and writes fixed local launchd configuration outside the signed bundles. It does not edit the signed installer or invoke its install branch.

Upgrades retain preferences and rules. Original bundles and service configuration are moved aside on the same filesystem so handled errors and interrupts can restore their file identities and restart the preceding installation. Recovery files are retained if restoration fails. This is not a power-loss recovery journal. Legacy beta installations must be uninstalled first. The unchanged upstream uninstaller handles removal.

## Verified behavior

On November 12, 2026, a fresh Apple macOS 27.2.1 (26B131) Tart VM was tested with Gatekeeper enabled. BlockBlock was downloaded in Safari, and its installer, daemon and helper passed `spctl --assess --type execute` as `Notarized Developer ID` with quarantine present on their bundles and executables.

The tests covered fresh installation, normal first-launch and Full Disk Access approvals, a real alert for a harmless persistence fixture, same-version reinstall, an upgrade from unchanged signed 2.4.4 payloads prepared with the preserving helper, and startup after reboot and login. Upgrade preferences and rules matched byte for byte. Injected failure and TERM-signal tests restored the original 2.4.4 files and both processes. The upstream uninstaller removed the apps, service, state and login entry. An unsigned app was rejected by Gatekeeper, missing nested quarantine was rejected before installation, and an altered local helper was rejected before execution.

These are direct installer lifecycle tests, not a full Homebrew installation inside the VM. Older macOS versions and Intel execution were not tested; the upstream universal signatures were verified for both architectures. Repository CI checks parsing and syntax without installing BlockBlock.
