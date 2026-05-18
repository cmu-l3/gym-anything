#!/bin/bash
# pre_task hook for family_accessibility_elderly on system_settings_env.
#
# Resets all 6 target accessibility settings to their defaults (opposite of
# task targets) so a do-nothing agent cannot collect baseline credit.
# Per Anti-Pattern #7 ("Update-Style Setup Does Not Reset the Target Fields"):
# every field the agent must set is explicitly forced to its baseline value.
# Per Anti-Pattern #10: setup stdout never echoes the target values.
set -eu

echo "=== Setting up family_accessibility_elderly ==="

# ---------------------------------------------------------------------------
# 1) Reset all 6 target settings to baseline (OFF / default) values.
# ---------------------------------------------------------------------------

# C1 baseline: Increase Contrast disabled (default = absent / 0)
defaults write com.apple.universalaccess increaseContrast -bool false

# C2 baseline: Reduce Transparency disabled (default = absent / 0)
defaults write com.apple.universalaccess reduceTransparency -bool false

# C3 baseline: Cursor size at system default (1.0 = normal size)
defaults write com.apple.universalaccess cursorSize -float 1.0

# C4 baseline: Scroll-wheel zoom disabled
defaults write com.apple.universalaccess closeViewScrollWheelToggle -bool false

# C5 baseline: Sticky Keys disabled
defaults write com.apple.universalaccess stickyKey -bool false

# C6 baseline: Slow Keys disabled
defaults write com.apple.universalaccess slowKey -bool false

# ---------------------------------------------------------------------------
# 2) Flush the prefs cache so the live UI reflects the baseline state.
# ---------------------------------------------------------------------------
killall cfprefsd 2>/dev/null || true
sleep 1

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

echo "=== family_accessibility_elderly setup complete ==="
echo "System Settings is open. Agent must configure 6 Accessibility settings."
