#!/bin/bash
# pre_task hook for presentation_mode_setup on system_settings_env.
#
# Responsibilities (per 14_task_design_antipatterns.md Anti-Pattern #7
# "Update-Style Setup Does Not Reset the Target Fields"):
#   1. Force every one of the 5 target settings to the OPPOSITE value of
#      the task target, so a do-nothing agent cannot collect baseline credit.
#   2. Restart the daemons that READ those prefs (Dock, SystemUIServer) so
#      the live UI reflects the baseline state when System Settings opens.
#   3. Record an authoritative task_start unix timestamp.
#   4. Launch System Settings and wait for the window to register.
#
# We do NOT echo the target values that the agent must reach — output is
# baseline information only (Anti-Pattern #10 "Embedded Language `print()`
# Calls Leaking Ground Truth in Setup Scripts"). The task description IS
# allowed to name target values (this is a `medium` task per the difficulty
# table in 01_core_principles.md); but setup-script stdout is treated as
# potentially agent-visible and must not redundantly disclose them.
set -eu

echo "=== Setting up presentation_mode_setup ==="

# ---------------------------------------------------------------------------
# 1) Reset every target setting to its baseline (opposite of task target).
# ---------------------------------------------------------------------------

# C1 baseline: Light appearance. macOS represents Light as the absence of
# the AppleInterfaceStyle key — explicit "Light" string is not a valid value.
defaults delete -g AppleInterfaceStyle 2>/dev/null || true

# C2 baseline: Dock at the bottom of the screen.
defaults write com.apple.dock orientation -string "bottom"

# C3 baseline: Dock auto-hide disabled.
defaults write com.apple.dock autohide -bool false

# C4 baseline: Dock tilesize at the system default of 48 px (mid-slider).
defaults write com.apple.dock tilesize -int 48

# C5 baseline: 12-hour clock with AM/PM marker. macOS exposes the 24-hour
# vs 12-hour choice via TWO complementary signals (probed live 2026-05):
#   1. `DateFormat` — a Unicode TS#35 pattern string. Lowercase `h` = 12-hour;
#      uppercase `HH` = 24-hour.
#   2. `ShowAMPM` — Boolean. The System Settings UI's "Show AM/PM" toggle in
#      Clock Options writes this key; setting it to false makes the menu
#      bar render 24-hour without changing DateFormat. (Live probe on the
#      use.computer fleet: toggling Show AM/PM off in the UI set
#      ShowAMPM=0 but left DateFormat as `"EEE MMM d  h:mm a"`.)
# We reset BOTH to 12-hour baseline so a do-nothing agent can't accidentally
# inherit a 24-hour clock from a stale plist.
defaults write com.apple.menuextra.clock DateFormat -string "EEE MMM d  h:mm a"
defaults write com.apple.menuextra.clock ShowAMPM -bool true
defaults write com.apple.menuextra.clock IsAnalog -bool false

# ---------------------------------------------------------------------------
# 2) Restart the daemons that read these prefs so the visible UI matches
# the baseline when the agent first sees System Settings.
#
# - Dock reads orientation/autohide/tilesize once at launch.
# - SystemUIServer manages the menu bar (clock format) and dark-mode
#   appearance switching.
# - cfprefsd ensures `defaults read` from later scripts sees the writes.
# ---------------------------------------------------------------------------
killall cfprefsd 2>/dev/null || true
sleep 1
killall Dock 2>/dev/null || true
killall SystemUIServer 2>/dev/null || true
sleep 2   # allow Dock/SystemUIServer to respawn

# ---------------------------------------------------------------------------
# 3) Record task_start unix epoch (verifier may use it to gate freshness).
# ---------------------------------------------------------------------------
date +%s > /tmp/task_start_timestamp
echo "task_start_unix=$(cat /tmp/task_start_timestamp)"

# ---------------------------------------------------------------------------
# 4) Launch System Settings and wait for window registration. Per the
# preview_env lesson (12_macos_environments.md "lsappinfo Regex"), match
# the bundle-path line, not the process-name line.
# ---------------------------------------------------------------------------
if ! pgrep -x "System Settings" >/dev/null; then
  open -a "System Settings"
fi
for i in $(seq 1 30); do
  if /usr/bin/lsappinfo list 2>/dev/null | grep -qiE 'System Settings\.app'; then
    echo "System Settings registered after ${i}s"
    break
  fi
  sleep 1
done
sleep 2

# Capture a start-state screenshot for the trajectory archive.
/usr/sbin/screencapture -x /tmp/task_start.png 2>/dev/null || true

echo "=== presentation_mode_setup setup complete ==="
echo "System Settings is open. Agent must adjust five settings (see description)."
