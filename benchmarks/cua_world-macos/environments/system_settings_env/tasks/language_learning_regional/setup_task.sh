#!/bin/bash
# pre_task hook for language_learning_regional on system_settings_env.
#
# Resets language, region, and clock settings to English/US/Imperial baseline
# so a do-nothing agent cannot collect credit from pre-existing configuration.
# Anti-Pattern #7: every field the agent must change is explicitly reset.
# Anti-Pattern #10: no target values echoed to stdout.
set -eu

echo "=== Setting up language_learning_regional ==="

# ---------------------------------------------------------------------------
# 1) Reset language and region to US English baseline.
# ---------------------------------------------------------------------------

# C1 baseline: English-only preferred languages list.
# Write as a proper array plist (the correct syntax for defaults write -array).
defaults write -g AppleLanguages -array "en-US"

# C2 baseline: Measurement system in US customary units (Inches).
defaults write -g AppleMeasurementUnits -string "Inches"
defaults write -g AppleMetricUnits -bool false

# C3 baseline: Temperature in Fahrenheit.
defaults write -g AppleTemperatureUnit -string "Fahrenheit"

# C4 baseline: 12-hour time format.
# AppleICUForce24HourTime = NO forces 12-hour. Delete first to ensure clean state.
defaults delete -g AppleICUForce24HourTime 2>/dev/null || true
# Also reset the menuextra clock format to 12-hour baseline.
defaults write com.apple.menuextra.clock DateFormat -string "EEE MMM d  h:mm a"
defaults write com.apple.menuextra.clock ShowAMPM -bool true

# C5 baseline: First day of week = Sunday (gregorian calendar value 1).
# The plist stores this as a dict; write via Python to ensure correct type.
/usr/bin/python3 - << 'PYEOF'
import subprocess, sys
# Write the AppleFirstWeekday dict to NSGlobalDomain.
# Value 1 = Sunday (US default), value 2 = Monday (European/French standard).
result = subprocess.run(
    ['defaults', 'write', '-g', 'AppleFirstWeekday', '-dict', 'gregorian', '1'],
    capture_output=True, text=True
)
if result.returncode != 0:
    print(f"WARN: Could not reset AppleFirstWeekday: {result.stderr.strip()}", file=sys.stderr)
else:
    print("AppleFirstWeekday reset to Sunday (1)")
PYEOF

# ---------------------------------------------------------------------------
# 2) Flush prefs cache and restart SystemUIServer to apply clock changes.
# ---------------------------------------------------------------------------
killall cfprefsd 2>/dev/null || true
sleep 1
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

echo "=== language_learning_regional setup complete ==="
echo "System Settings is open. Agent must configure language, region, and time format settings."
