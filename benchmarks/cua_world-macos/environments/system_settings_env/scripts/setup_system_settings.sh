#!/bin/bash
# Configure the System Settings environment with a deterministic baseline so
# tasks can compute deltas. We DO NOT pre-configure the specific values that
# individual tasks check — that's each task's setup_task.sh job (see
# Anti-Pattern #7 in 14_task_design_antipatterns.md "Update-Style Setup Does
# Not Reset the Target Fields"). Here we only:
#
#   - Force-quit any prior System Settings instance so each task starts with
#     a clean window state.
#   - Pre-create the standard user dirs tasks may touch (~/Documents,
#     ~/Downloads).
#   - Flush cfprefsd so subsequent reads pick up writes promptly.
#
# All settings the tasks care about (NSGlobalDomain AppleInterfaceStyle,
# com.apple.dock, com.apple.menuextra.clock, etc.) are reset per-task in
# setup_task.sh, NOT here, because their baselines vary by task.
set -eu

# Quit any leftover System Settings so the per-task pre_task hook starts
# from a deterministic launch. SIGTERM via osascript first (graceful), then
# SIGKILL via pkill as backstop. osascript over SSH cannot walk the AX
# tree (TCC trap) but the high-level `tell app to quit` does work because
# it uses Apple Events / LaunchServices, not Accessibility.
osascript -e 'tell application "System Settings" to quit' 2>/dev/null || true
sleep 1
pkill -x "System Settings" 2>/dev/null || true
pkill -x "System Preferences" 2>/dev/null || true   # in case a legacy build runs
sleep 1

# Pre-create the user dirs task setup scripts may write to.
mkdir -p "$HOME/Documents" "$HOME/Downloads" "$HOME/Library/Preferences"

# Flush cfprefsd so the per-task `defaults write` calls in setup_task.sh
# are not racing the previous cache. cfprefsd respawns on next access.
killall cfprefsd 2>/dev/null || true
sleep 1

echo "[setup] System Settings env baseline ready"
echo "[setup] System Settings bundle present at:"
ls -d "/System/Applications/System Settings.app" "/Applications/System Settings.app" 2>/dev/null | head -1 | xargs -I {} echo "[setup]   {}"
echo "[setup] OK"
