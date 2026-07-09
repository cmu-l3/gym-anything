#!/bin/bash
# pre_task hook for home_office_productivity on system_settings_env.
#
# Resets all 5 target settings to their system defaults so a do-nothing agent
# cannot collect credit from pre-existing configuration.
# Anti-Pattern #7: every field the agent must change is explicitly reset.
# Anti-Pattern #10: no target values echoed to stdout.
set -eu

echo "=== Setting up home_office_productivity ==="

# ---------------------------------------------------------------------------
# 1) Reset all 5 target settings to baseline (default) values.
# ---------------------------------------------------------------------------

# C1 baseline: Appearance = Light (not Auto).
# Auto appearance is signalled by AppleInterfaceStyleSwitchesAutomatically=1.
# We delete both keys to ensure a clean Light (manual) state.
defaults delete -g AppleInterfaceStyle 2>/dev/null || true
defaults delete -g AppleInterfaceStyleSwitchesAutomatically 2>/dev/null || true

# C2 baseline: Scroll bars = Automatic (appear when scrolling, then hide).
defaults write -g AppleShowScrollBars -string "Automatic"

# C3 baseline: UI sound effects enabled.
# The key is com.apple.sound.beep.feedback in NSGlobalDomain; 1 = sounds on.
defaults write -g com.apple.sound.beep.feedback -int 1

# C4 baseline: Show recent apps in Dock = true (system default).
defaults write com.apple.dock show-recents -bool true

# C5 baseline: Minimize effect = genie (system default).
defaults write com.apple.dock mineffect -string "genie"

# ---------------------------------------------------------------------------
# 2) Flush prefs cache and restart Dock / SystemUIServer.
# ---------------------------------------------------------------------------
killall cfprefsd 2>/dev/null || true
sleep 1
killall Dock 2>/dev/null || true
killall SystemUIServer 2>/dev/null || true
sleep 2

# ---------------------------------------------------------------------------
# 3) Record task_start unix epoch.
# ---------------------------------------------------------------------------
date +%s > /tmp/task_start_timestamp
echo "task_start_unix=$(cat /tmp/task_start_timestamp)"

# ---------------------------------------------------------------------------
# 4) Launch System Settings and wait for window registration.
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

/usr/sbin/screencapture -x /tmp/task_start.png 2>/dev/null || true

echo "=== home_office_productivity setup complete ==="
echo "System Settings is open. Agent must configure appearance, sound, scroll bars, and Dock."
