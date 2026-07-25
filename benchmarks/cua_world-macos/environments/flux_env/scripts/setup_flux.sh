#!/bin/bash
# post_start: seed baseline f.lux preferences so first launch produces a
# deterministic state.
#
#   - SUEnableAutomaticChecks / SUHasLaunchedBefore: suppress Sparkle update
#     prompts and the first-launch "checking for updates" UI.
#   - SUSendProfileInfo: don't phone home with system profile.
#   - lat / lng / place: seed a default location (Pittsburgh, PA) so the
#     first-run "Where are you?" location dialog is skipped. Pref-key names
#     vary slightly across Flux versions — incorrect keys are silently
#     ignored, so worst-case the first-run dialog appears once.
#
# All writes flow through cfprefsd; we kill it at the end so the values are
# flushed before the first `open -a Flux` call.
set -eu

DOMAIN="org.herf.Flux"

# Sparkle (auto-update framework) prompts
defaults write "$DOMAIN" SUEnableAutomaticChecks -bool false
defaults write "$DOMAIN" SUHasLaunchedBefore -bool true
defaults write "$DOMAIN" SUSendProfileInfo -bool false

# Deterministic location (Pittsburgh, PA — chosen as a stable, well-known
# coordinate; tasks that require a different location override these in
# their own setup_task.sh).
defaults write "$DOMAIN" lat -float 40.4406
defaults write "$DOMAIN" lng -float -79.9959
defaults write "$DOMAIN" place -string "Pittsburgh, PA"

echo "[setup] f.lux preferences seeded"

# Flush the cfprefsd cache so the freshly-written defaults are visible to
# Flux on its first launch — same lesson as setup_safari.sh.
killall cfprefsd 2>/dev/null || true
sleep 1
echo "[setup] cfprefsd flushed"

# Verify the bundle one more time (cheap defence against an install hook
# that succeeded but produced a corrupt bundle).
ls -d /Applications/Flux.app >/dev/null
echo "[setup] OK"
