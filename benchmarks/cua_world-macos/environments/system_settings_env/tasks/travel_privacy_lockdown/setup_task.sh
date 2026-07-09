#!/bin/bash
# pre_task hook for travel_privacy_lockdown on system_settings_env.
#
# Resets all 5 target privacy/security settings to open/default baseline
# so a do-nothing agent cannot collect credit from pre-existing configuration.
# Anti-Pattern #7: every field the agent must change is explicitly reset.
# Anti-Pattern #10: no target values echoed to stdout.
set -eu

echo "=== Setting up travel_privacy_lockdown ==="

# ---------------------------------------------------------------------------
# 1) Reset all 5 target settings to baseline (open/non-secure) values.
# ---------------------------------------------------------------------------

# C1 baseline: Light appearance (absence of AppleInterfaceStyle key = Light)
defaults delete -g AppleInterfaceStyle 2>/dev/null || true

# C2 baseline: Screen saver idle time = 300 seconds (5 minutes — permissive)
defaults write com.apple.screensaver idleTime -int 300

# C3 baseline: No password required on screensaver/wake
defaults write com.apple.screensaver askForPassword -int 0

# C4 baseline: Password delay = 5 seconds (grace period)
defaults write com.apple.screensaver askForPasswordDelay -int 5

# C5 baseline: Top-left hot corner disabled (0 = no action)
defaults write com.apple.dock wvous-tl-corner -int 0
defaults write com.apple.dock wvous-tl-modifier -int 0

# ---------------------------------------------------------------------------
# 2) Flush prefs cache and restart affected daemons.
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

echo "=== travel_privacy_lockdown setup complete ==="
echo "System Settings is open. Agent must configure appearance, screensaver, lock screen, and hot corner."
