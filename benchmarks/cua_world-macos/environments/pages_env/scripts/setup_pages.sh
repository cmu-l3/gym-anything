#!/bin/bash
# Configure Apple Pages for task work:
#   - Suppress the persistent "New Version of Pages Available" upgrade modal.
#     The base-macos image ships Pages 14.5, but Apple now prompts users to
#     upgrade to Pages 15 on every launch. Probed live: the modal is gated on
#     TMAApplicationUpdateNotifier.MigrationAlertToInstallCallCounter; setting
#     it to a large value (with cfprefsd flush) keeps the alert from appearing
#     and the document area accessible to the agent on first launch.
#   - Disable autocorrect / smart-quote substitution / dash substitution at the
#     global level so typed phrases like "AI-assisted onboarding" and
#     "Q3 OKR target: $5M" aren't silently rewritten before the verifier sees
#     them. Pages reads these from NSGlobalDomain.
#   - Pre-create ~/Documents (where tasks save .pages files).
#
# All settings go through `defaults`, not plist surgery, so launch-time
# cfprefsd cache picks them up.
set -eu

DOMAIN="com.apple.iWork.Pages"

# Suppress the "New Version of Pages Available" alert. Three keys observed live
# in the pref domain when Pages prompts; setting them all to high values plus
# a far-future last-shown timestamp keeps the modal from re-appearing.
defaults write "$DOMAIN" "TMAApplicationUpdateNotifier.MigrationAlertToInstallCallCounter" -int 9999
defaults write "$DOMAIN" "TMAApplicationUpdateNotifier.MigrationAlertToUpgradeCallCounter" -int 9999
defaults write "$DOMAIN" "TMAApplicationUpdateNotifier.MigrationAlertToInstallLastShownTimeStamp" -string "9999999999.0"
defaults write "$DOMAIN" "TMAApplicationUpdateNotifier.MigrationAlertToUpgradeLastShownTimeStamp" -string "9999999999.0"

# Suppress the first-launch "iCloud document storage" prompt some Pages builds
# show; harmless if the key isn't recognized.
defaults write "$DOMAIN" "TSAUseCloudKitStorageDefault" -bool false

# Quiet the global text-substitution layer. NSGlobalDomain keys apply to every
# Cocoa text view including Pages. Without these, the agent's typed phrases
# can be silently rewritten (e.g. "--" -> em-dash, "(c)" -> \u00a9, $5M ->
# $5\u202fmillion in some locales) which would break verifier phrase checks.
defaults write -g NSAutomaticSpellingCorrectionEnabled -bool false
defaults write -g NSAutomaticDashSubstitutionEnabled -bool false
defaults write -g NSAutomaticQuoteSubstitutionEnabled -bool false
defaults write -g NSAutomaticTextReplacementEnabled -bool false
defaults write -g NSAutomaticCapitalizationEnabled -bool false
defaults write -g NSAutomaticPeriodSubstitutionEnabled -bool false

# Suppress the macOS-level "Updates Available \u2014 Do you want to install these
# updates tonight?" Notification Center banner and the macOS "Tips" notification
# (com.apple.tips). These don't obstruct the Pages document area but appear in
# every screenshot, which is visually distracting in evidence packages. Audit
# finding 2026-05.
defaults write com.apple.SoftwareUpdate AutomaticCheckEnabled -bool false
defaults write com.apple.SoftwareUpdate AutomaticDownload -bool false
defaults write com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates -bool false
defaults write com.apple.SoftwareUpdate ConfigDataInstall -bool false
defaults write com.apple.SoftwareUpdate CriticalUpdateInstall -bool false
defaults write com.apple.tips ShowTips -bool false 2>/dev/null || true

# Pre-create the user-visible save directory tasks write into.
mkdir -p "$HOME/Documents"

echo "[setup] Pages preferences seeded"

# Flush cfprefsd cache so Pages picks up the migration-alert suppressors on
# first launch. Without this, the upgrade modal still appears on the very
# first launch and the agent has to dismiss it manually.
killall cfprefsd 2>/dev/null || true
sleep 1
echo "[setup] cfprefsd flushed"

# Restart NotificationCenter so any already-queued macOS notifications (the
# "Updates Available" and "Tips" banners that appear on first boot of the
# sandbox) get dismissed before screenshots. Without this, the suppression
# defaults above prevent future banners but the current one stays on screen.
killall NotificationCenter 2>/dev/null || true
killall usernoted 2>/dev/null || true
sleep 1
echo "[setup] NotificationCenter restarted (clears pending banners)"

echo "[setup] verifying Pages bundle one more time:"
ls -d /Applications/Pages.app >/dev/null
echo "[setup] OK"
