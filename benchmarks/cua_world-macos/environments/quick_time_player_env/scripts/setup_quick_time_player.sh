#!/bin/bash
# Configure QuickTime Player for task work:
#   - Suppress the file-open dialog QuickTime pops on launch with no document
#     (NSShowAppCentricOpenPanelInsteadOfUntitledFile = false). Like Preview,
#     QuickTime is a document-based AppKit app; without this key it presents
#     a modal NSOpenPanel before showing any window, blocking screenshot
#     determinism and any agent that doesn't dismiss the dialog first.
#   - Disable the global "reopen windows when re-launching" prompt
#     (NSQuitAlwaysKeepsWindows) so each reset starts with no restored
#     documents or recording windows.
#   - Pre-create ~/Movies, ~/Documents, ~/Desktop — the canonical paths
#     QuickTime offers when saving recordings / exports.
#
# All settings go through `defaults`. The QuickTime Player prefs domain is
# `com.apple.QuickTimePlayerX` (the "X" suffix dates back to the QT10 rewrite
# in Snow Leopard and is still the active domain on macOS 15). Probed via
# `defaults read com.apple.QuickTimePlayerX` on the use.computer fleet.
set -eu

DOMAIN="com.apple.QuickTimePlayerX"

# Skip the file-open NSOpenPanel that pops up on first launch.
defaults write "$DOMAIN" NSShowAppCentricOpenPanelInsteadOfUntitledFile -bool false

# Suppress per-recording "Save" prompt nags / "delete unsaved recording" alerts
# that would otherwise block reset on a re-launch with a partial recording in
# memory. (Document-based AppKit apps honor the global ApplePersistence and
# NSQuitAlwaysKeepsWindows keys; we write both for belt-and-suspenders.)
defaults write -globalDomain NSQuitAlwaysKeepsWindows -bool false
defaults write -globalDomain ApplePersistence -bool false

# Make sure dirs exist that tasks read from / write to.
mkdir -p "$HOME/Downloads" "$HOME/Documents" "$HOME/Movies" "$HOME/Desktop"

# Suppress the system "Updates Available" / "Tips Notification" toasts that
# otherwise show up in the upper-right corner of every screenshot. They don't
# block agent input but they're distractors for VLM grounding and they make
# the evidence screenshots noisier. Observed live during the launch_quick_time_player
# interactive pilot — see evidence_docs/launch_quick_time_player/live_smoke/.
# Same suppression pattern as apple_notes_env/scripts/setup_apple_notes.sh.
defaults write com.apple.SoftwareUpdate AutomaticDownload -bool false 2>/dev/null || true
defaults write com.apple.SoftwareUpdate AutomaticCheckEnabled -bool false 2>/dev/null || true
defaults write com.apple.notificationcenterui doNotDisturb -bool true 2>/dev/null || true
defaults -currentHost write com.apple.notificationcenterui doNotDisturb -bool true 2>/dev/null || true

echo "[setup] QuickTime Player preferences seeded"

# Flush cfprefsd cache so QuickTime Player picks up the new defaults on first
# launch. Without this, NSShowAppCentricOpenPanelInsteadOfUntitledFile is
# observed to still produce the Open dialog on the first reset.
killall cfprefsd 2>/dev/null || true
sleep 1
echo "[setup] cfprefsd flushed"

echo "[setup] verifying QuickTime Player bundle one more time:"
ls -d "/Applications/QuickTime Player.app" "/System/Applications/QuickTime Player.app" 2>/dev/null | head -1 \
  | xargs -I {} echo "[setup] found {}"
echo "[setup] OK"
