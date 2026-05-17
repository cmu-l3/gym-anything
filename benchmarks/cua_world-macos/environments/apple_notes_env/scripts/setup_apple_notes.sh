#!/bin/bash
# Configure Apple Notes for task work:
#   - Make sure the on-disk state dirs exist (Notes lazily creates them on
#     first launch, but pre-creating means file reads in setup_task.sh and
#     export_result.sh don't trip on ENOENT before the agent ever runs).
#   - Set a conservative pref baseline so first-launch UI is deterministic.
#
# All settings go through `defaults`, NOT plist surgery, so the launch-time
# cfprefsd cache picks them up correctly.
set -eu

DOMAIN="com.apple.Notes"

# Disable "open windows when quitting" so quitting Notes during export hooks
# doesn't leave a windowed Notes process alive on next launch.
defaults write "$DOMAIN" NSQuitAlwaysKeepsWindows -bool false

# Suppress autocorrection / autocomplete that could rewrite agent-typed text.
# Tasks pin exact phrases in the verifier; autocorrect of "OKR" -> "OK" or
# "$5M" -> "$5 million" would break those checks for no good reason.
defaults write "$DOMAIN" WebAutomaticSpellingCorrectionEnabled -bool false
defaults write "$DOMAIN" NSAutomaticSpellingCorrectionEnabled -bool false
defaults write "$DOMAIN" NSAutomaticDashSubstitutionEnabled -bool false
defaults write "$DOMAIN" NSAutomaticQuoteSubstitutionEnabled -bool false
defaults write "$DOMAIN" NSAutomaticTextReplacementEnabled -bool false

# Default editor view: rich text body, no fancy first-run pane.
defaults write "$DOMAIN" DefaultEditorViewSize -int 1

# Pre-create the user-visible dirs the verifier may peek into. Notes itself
# creates them on first launch under ~/Library/Group Containers, but other
# task-specific scripts may write there too.
mkdir -p "$HOME/Documents"
mkdir -p "$HOME/Library/Group Containers/group.com.apple.notes"
mkdir -p "$HOME/Library/Containers/com.apple.Notes/Data"

# Suppress the system notification toasts that otherwise show up in the
# upper-right of every screenshot ("Updates Available", "Tips Notification").
# They don't overlap the Notes window so they don't block agent input, but
# they're distractors for VLM grounding steps and they make the evidence
# screenshots look noisier than they need to.
defaults write com.apple.SoftwareUpdate AutomaticDownload -bool false 2>/dev/null || true
defaults write com.apple.SoftwareUpdate AutomaticCheckEnabled -bool false 2>/dev/null || true
# Set Notification Center to Do-Not-Disturb. Key changed across macOS versions;
# write both the legacy doNotDisturb flag and the newer Focus-mode equivalent
# so we cover whatever version the use.computer base-macos image ships.
defaults write com.apple.notificationcenterui doNotDisturb -bool true 2>/dev/null || true
defaults -currentHost write com.apple.notificationcenterui doNotDisturb -bool true 2>/dev/null || true

echo "[setup] Apple Notes preferences seeded"

# Flush cfprefsd cache so Notes picks up the new defaults on first launch.
killall cfprefsd 2>/dev/null || true
sleep 1
echo "[setup] cfprefsd flushed"

echo "[setup] verifying Notes bundle one more time:"
ls -d /Applications/Notes.app /System/Applications/Notes.app 2>/dev/null | head -1 >/dev/null \
  || { echo "[setup] FAILED — no Notes bundle in either /Applications or /System/Applications" >&2; exit 1; }
echo "[setup] OK"
