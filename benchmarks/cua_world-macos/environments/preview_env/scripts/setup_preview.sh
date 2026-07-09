#!/bin/bash
# Configure Preview for task work:
#   - Suppress the "Open Recent" / iCloud document picker that pops up when
#     Preview is launched with no file (NSShowAppCentricOpenPanelInsteadOfUntitledFile)
#   - Disable automatic window restoration (NSQuitAlwaysKeepsWindows) so each
#     reset starts from a clean state.
#   - Pre-create ~/Documents (where task source/output files live).
#
# All settings go through `defaults`. Preview is NOT sandboxed in the same way
# Safari is (no app-container path) — its prefs file is at the standard
# ~/Library/Preferences/com.apple.Preview.plist path. Probed via
# `defaults read com.apple.Preview` on the use.computer fleet.
set -eu

DOMAIN="com.apple.Preview"

# Skip the "What's new in Preview" splash + iCloud document picker on launch.
# (These keys are observed in macOS 14/15 builds of Preview; harmless on
# older versions where they're no-ops.)
defaults write "$DOMAIN" NSShowAppCentricOpenPanelInsteadOfUntitledFile -bool false

# Forward-looking defaults for future Preview tasks:
#   PVImageMaximumZoomFactor   — pins the maximum zoom so screenshot-based
#                                verifiers see a predictable image size when
#                                an agent zooms in (image-detail tasks).
#   PVPDFLastViewedBookmarksKey — empties the per-document "last page viewed"
#                                cache so PDF tasks always open at page 1.
# Neither is read by the currently-shipped `rotate_image_clockwise` task,
# but seeding them at env-creation time means future PDF / zoom tasks
# inherit a deterministic baseline without a setup-script change.
defaults write "$DOMAIN" PVImageMaximumZoomFactor -float 4.0
defaults write "$DOMAIN" PVPDFLastViewedBookmarksKey -array

# Make the global "reopen windows" prompt go away — Preview otherwise pops a
# modal asking whether to restore last session.
defaults write -globalDomain NSQuitAlwaysKeepsWindows -bool false
defaults write -globalDomain ApplePersistence -bool false

# Make sure dirs exist that tasks read/write
mkdir -p "$HOME/Downloads" "$HOME/Documents"

echo "[setup] Preview preferences seeded"

# Flush cfprefsd cache so Preview picks up new defaults on first launch.
killall cfprefsd 2>/dev/null || true
sleep 1
echo "[setup] cfprefsd flushed"

echo "[setup] verifying Preview bundle one more time:"
ls -d /Applications/Preview.app /System/Applications/Preview.app 2>/dev/null | head -1 | xargs -I {} echo "[setup] found {}"
echo "[setup] OK"
