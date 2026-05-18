#!/bin/bash
# pre_task hook for creative_night_owl_setup on system_settings_env.
#
# Resets all 5 target settings to baseline values so a do-nothing agent
# cannot collect credit from pre-existing configuration.
# Anti-Pattern #7: every field the agent must change is explicitly reset.
# Anti-Pattern #10: no target values are echoed to stdout.
set -eu

echo "=== Setting up creative_night_owl_setup ==="

# ---------------------------------------------------------------------------
# 1) Reset all 5 target settings to their baseline values.
# ---------------------------------------------------------------------------

# C1 baseline: Reduce Motion disabled (key absent = disabled; delete to be safe)
defaults delete -g AppleReduceMotion 2>/dev/null || true

# C2 baseline: Key Repeat at the system default (6 = medium speed)
# Lower value = faster. Fastest is 2. We set baseline to 6.
defaults write -g KeyRepeat -int 6

# C3 baseline: Delay Until Repeat at the system default (25 = medium delay)
# Lower value = shorter delay. Shortest is 15. We set baseline to 25.
defaults write -g InitialKeyRepeat -int 25

# C4 baseline: Bottom-left hot corner disabled (0 = no action)
defaults write com.apple.dock wvous-bl-corner -int 0
defaults write com.apple.dock wvous-bl-modifier -int 0

# C5 baseline: Top-right hot corner disabled (0 = no action)
defaults write com.apple.dock wvous-tr-corner -int 0
defaults write com.apple.dock wvous-tr-modifier -int 0

# ---------------------------------------------------------------------------
# 2) Flush prefs cache and restart Dock so hot corner changes take effect.
# ---------------------------------------------------------------------------
killall cfprefsd 2>/dev/null || true
sleep 1
killall Dock 2>/dev/null || true
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

echo "=== creative_night_owl_setup setup complete ==="
echo "System Settings is open. Agent must configure keyboard repeat, hot corners, and motion settings."
