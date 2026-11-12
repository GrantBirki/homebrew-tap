#!/bin/bash
set -Eeuo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
umask 077
quarantine_value() {
  local attributes
  attributes=$(xattr "$1") || return 1
  if grep -qx com.apple.quarantine <<< "$attributes"; then
    xattr -px com.apple.quarantine "$1"
  else
    printf 'absent\n'
  fi
}
[[ $EUID == 0 && $# == 1 ]] || { echo 'Run as root with the extracted installer app path.' >&2; exit 1; }
operator=$(stat -f %Su /dev/console)
[[ $operator != root && $operator != loginwindow ]] || { echo 'A logged-in operator is required.' >&2; exit 1; }
operator_uid=$(id -u "$operator")
state=/Library/Objective-See/BlockBlock
helper='/Applications/BlockBlock Helper.app'
plist=/Library/LaunchDaemons/com.objective-see.blockblock.plist
label=system/com.objective-see.blockblock
for path in /Library/Objective-See "$state" "$state/BlockBlock.app" "$state/preferences.plist" "$helper" "$plist"; do
  [[ ! -L $path ]] || { echo "Refusing symlink: $path" >&2; exit 1; }
done
[[ ! -e /Library/LaunchDaemons/com.objectiveSee.blockblock.plist ]] || { echo 'Uninstall the legacy beta before using this installer.' >&2; exit 1; }
source_quarantine=$(quarantine_value "$1")
[[ $source_quarantine != absent ]] || { echo 'Use the normally quarantined Homebrew-staged installer bundle.' >&2; exit 1; }
work=$(mktemp -d /private/tmp/blockblock-install.XXXXXX)
cleanup=true
trap 'if $cleanup; then rm -rf "$work"; else echo "Recovery files retained at $work" >&2; fi' EXIT
# Take a protected snapshot before verifying or reading the downloaded payload.
ditto "$1" "$work/installer.app"
[[ -d $work/installer.app && ! -L $work/installer.app ]] || { echo 'Expected a regular installer bundle.' >&2; exit 1; }
# This exact release contains only regular files and directories.
other_files=$(find "$work/installer.app" ! -type f ! -type d -print)
[[ -z $other_files ]] || { echo 'Unexpected special files in the installer snapshot.' >&2; exit 1; }
[[ $(quarantine_value "$work/installer.app") == "$source_quarantine" ]] || { echo 'Snapshot did not preserve quarantine.' >&2; exit 1; }
chown -R root:wheel "$work/installer.app"
chmod -RN "$work/installer.app"
chmod -R go-w "$work/installer.app"
requirement='=anchor apple generic and identifier "com.objective-see.blockblock.installer" and certificate leaf[subject.OU] = "VBG97UB4TA" and (cdhash H"88aa8ff0aacceb17126fcafe62c949b5e3a64f98" or cdhash H"58fa97faa220f6ec8a9aec136fd31c01679f7f4b")'
codesign --verify --deep --strict --all-architectures -R "$requirement" "$work/installer.app"
resources="$work/installer.app/Contents/Resources"
require_bundle_quarantine() {
  local app="$1" executable
  executable=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Contents/Info.plist")
  [[ -n $executable && $executable != */* ]] || return 1
  for item in "$app" "$app/Contents/MacOS/$executable"; do
    [[ $(quarantine_value "$item") != absent ]] || { echo "Missing staged quarantine: $item" >&2; return 1; }
  done
}
for app in "$work/installer.app" "$resources/BlockBlock.app" "$resources/BlockBlock Helper.app"; do
  require_bundle_quarantine "$app"
  spctl --assess --type execute --verbose=4 "$app"
done

login_item() {
  launchctl asuser "$operator_uid" sudo -H -u "$operator" osascript -l JavaScript - "$1" "$helper" <<'JXA'
ObjC.import('Foundation');
ObjC.import('CoreServices');
function matchingItems(list, path) {
    var entries = ObjC.castRefToObject($.LSSharedFileListCopySnapshot(list, null));
    var matches = [];
    for (var i = 0; i < entries.count; i++) {
        var entry = entries.objectAtIndex(i);
        var url = ObjC.castRefToObject($.LSSharedFileListItemCopyResolvedURL(entry, 0, null));
        if (ObjC.unwrap(url) && ObjC.unwrap(url.path) === path) matches.push(entry);
    }
    return matches;
}
function run(args) {
    var list = $.LSSharedFileListCreate(null, $.kLSSharedFileListSessionLoginItems, null);
    var entries = matchingItems(list, args[1]);
    if (args[0] === 'remove') {
        entries.forEach(function(entry) {
            if ($.LSSharedFileListItemRemove(list, entry) !== 0) throw new Error('Login item removal failed');
        });
    }
    if (args[0] === 'add' && entries.length === 0) {
        $.LSSharedFileListInsertItemURL(list, $.kLSSharedFileListItemLast, null, null, $.NSURL.fileURLWithPath(args[1]), null, null);
    }
    var present = matchingItems(list, args[1]).length > 0;
    if ((args[0] === 'add' && !present) || (args[0] === 'remove' && present)) throw new Error('Login item verification failed');
    return args[0] === 'add' && entries.length === 0 ? 'added' : present ? 'present' : 'absent';
}
JXA
}

# Check registration support before stopping an existing installation.
login_item status >/dev/null
targets=("$state/BlockBlock.app" "$helper" "$plist")
backups=("$work/old-daemon.app" "$work/old-helper.app" "$work/old-service.plist")
for index in 0 1 2; do
  target=${targets[$index]}
  if [[ -e $target ]]; then
    [[ $(stat -f %d "$target") == $(stat -f %d "$work") ]] || { echo 'Installation paths must share the recovery filesystem.' >&2; exit 1; }
  else
    touch "$work/absent-$index"
  fi
done
old_loaded=false
launchctl print "$label" >/dev/null 2>&1 && old_loaded=true
old_helper_running=false
pgrep -u "$operator_uid" -f '/BlockBlock Helper[.]app/Contents/MacOS/BlockBlock Helper' >/dev/null && old_helper_running=true
changed=false
new_preferences=false
login_added=false
rollback() {
  code=$1
  if (( BASH_SUBSHELL > 0 )); then exit "$code"; fi
  trap - ERR INT TERM
  set +e
  restore_failed=false
  if $changed; then
    launchctl bootout "$label" >/dev/null 2>&1
    killall 'BlockBlock Helper' >/dev/null 2>&1
    for index in 0 1 2; do
      target=${targets[$index]}; backup=${backups[$index]}
      if [[ -e $backup ]]; then
        rm -rf "$target" && mv "$backup" "$target" || restore_failed=true
      elif [[ -e $work/absent-$index ]]; then
        rm -rf "$target" || restore_failed=true
      fi
    done
    if $new_preferences; then rm -f "$state/preferences.plist" || restore_failed=true; fi
    if $login_added; then login_item remove || restore_failed=true; fi
    if $old_loaded; then launchctl bootstrap system "$plist" || restore_failed=true; fi
    if $old_helper_running; then
      launchctl asuser "$operator_uid" sudo -H -u "$operator" open "$helper" || restore_failed=true
    fi
  fi
  if $restore_failed; then
    cleanup=false
    echo 'BlockBlock installation failed and restoration was incomplete.' >&2
  else
    echo 'BlockBlock installation failed; preceding files were restored where present.' >&2
  fi
  exit "$code"
}
trap 'rollback $?' ERR
trap 'rollback 130' INT
trap 'rollback 143' TERM
for directory in /Library/Objective-See "$state"; do
  if [[ -e $directory ]]; then
    mode=$(stat -f %Lp "$directory")
    [[ -d $directory && $(stat -f %u "$directory") == 0 && $((8#$mode & 0022)) == 0 ]] || { echo "Unprotected installation directory: $directory" >&2; false; }
  else
    mkdir "$directory"
    chown root:wheel "$directory"
    chmod 755 "$directory"
  fi
done
changed=true
$old_loaded && launchctl bootout "$label"
killall 'BlockBlock Helper' >/dev/null 2>&1 || true
# Rename originals on the same filesystem so rollback preserves their identities.
for index in 0 1 2; do
  target=${targets[$index]}; backup=${backups[$index]}
  [[ ! -e $target ]] || mv "$target" "$backup"
done
ditto "$resources/BlockBlock.app" "$state/BlockBlock.app"
ditto "$resources/BlockBlock Helper.app" "$helper"
# This is fixed local service configuration, not a metadata-stripped downloaded plist.
cat > "$plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>com.objective-see.blockblock</string>
<key>MachServices</key><dict><key>com.objective-see.blockblock</key><true/></dict>
<key>ProgramArguments</key><array><string>/Library/Objective-See/BlockBlock/BlockBlock.app/Contents/MacOS/BlockBlock</string></array>
<key>RunAtLoad</key><true/>
<key>EnableTransactions</key><false/>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
chown root:wheel "$plist"
chmod 644 "$plist"
plist_attributes=$(xattr "$plist")
if grep -qx com.apple.quarantine <<< "$plist_attributes"; then
  echo 'The local service configuration is quarantined; refusing to remove its metadata.' >&2
  false
fi
if [[ ! -e $state/preferences.plist ]]; then
  new_preferences=true
  for key in disabled noIconMode passiveMode notarizationMode notarizationAllMode clickFixMode clickFixHeuristicsMode noupdateMode gotFullDiskAccess; do
    /usr/libexec/PlistBuddy -c "Add $key bool false" "$state/preferences.plist"
  done
  chown root:wheel "$state/preferences.plist"
  chmod 644 "$state/preferences.plist"
fi
# Compare quarantine on every file, including signed nested bundle contents.
for name in 'BlockBlock.app' 'BlockBlock Helper.app'; do
  source="$resources/$name"
  if [[ $name == 'BlockBlock.app' ]]; then target="$state/$name"; else target="$helper"; fi
  while IFS= read -r -d '' file; do
    relative=${file#"$source"}
    before=$(quarantine_value "$file")
    after=$(quarantine_value "$target$relative")
    [[ $before == "$after" ]] || { echo "Quarantine metadata changed: $name$relative" >&2; false; }
  done < <(find "$source" -print0)
done
for app in "$state/BlockBlock.app" "$helper"; do
  require_bundle_quarantine "$app"
  codesign --verify --deep --strict --all-architectures "$app"
  spctl --assess --type execute --verbose=4 "$app"
done
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$state/BlockBlock.app"
# Let macOS obtain normal first-launch consent before launchd runs the root daemon.
# Its entrypoint exits immediately as this ordinary user; monitoring runs under launchd.
echo 'Approve the normal macOS Open prompt for BlockBlock to finish installation.'
launchctl asuser "$operator_uid" sudo -H -u "$operator" open -W "$state/BlockBlock.app"
login_result=$(login_item add)
[[ $login_result != added ]] || login_added=true
launchctl bootstrap system "$plist"
for attempt in {1..20}; do
  if launchctl print "$label" | grep -Eq 'pid = [0-9]+'; then
    launchctl asuser "$operator_uid" sudo -H -u "$operator" open "$helper"
    trap - ERR INT TERM
    echo 'BlockBlock 2.5.2 daemon started. Full Disk Access still requires operator approval.'
    exit 0
  fi
  sleep .5
done
false
