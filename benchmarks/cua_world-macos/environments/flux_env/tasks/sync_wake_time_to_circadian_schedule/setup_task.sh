#!/bin/bash
# pre_task: seed the challenge baseline for sync_wake_time_to_circadian_schedule.
#
# Baseline state (all three must be fixed by the agent):
#   wakeTime = 480  (8:00 AM — agent must compute and set 315 = 5:15 AM)
#   SUEnableAutomaticChecks = true  (wrong — agent must set to false)
#   SUSendProfileInfo = true        (wrong — agent must set to false)
#
# Does NOT print the target wakeTime (315) — only the baseline (480).
set -eu

DOMAIN="org.herf.Flux"
PLIST="$HOME/Library/Preferences/org.herf.Flux.plist"

echo "=== Setting up sync_wake_time_to_circadian_schedule ==="

# 1) Quit any running Flux so plist writes are not overridden.
osascript -e 'tell application "Flux" to quit' 2>/dev/null || true
sleep 1
pkill -x Flux 2>/dev/null || true
sleep 1

# 2) Write the challenge baseline.
/usr/bin/defaults write "$DOMAIN" wakeTime              -int 480
/usr/bin/defaults write "$DOMAIN" SUEnableAutomaticChecks -bool true
/usr/bin/defaults write "$DOMAIN" SUSendProfileInfo       -bool true
/usr/bin/defaults write "$DOMAIN" SUHasLaunchedBefore     -bool true
/usr/bin/defaults write "$DOMAIN" lat    -float 40.4406
/usr/bin/defaults write "$DOMAIN" lng    -float -79.9959
/usr/bin/defaults write "$DOMAIN" place  -string "Pittsburgh, PA"

killall cfprefsd 2>/dev/null || true
sleep 1

# 3) Record baseline values for export_result.sh.
/usr/bin/stat -f '%m' "$PLIST" 2>/dev/null > /tmp/initial_plist_mtime   || echo "0" > /tmp/initial_plist_mtime
/usr/bin/stat -f '%z' "$PLIST" 2>/dev/null > /tmp/initial_plist_size    || echo "0" > /tmp/initial_plist_size
/usr/bin/defaults read "$DOMAIN" wakeTime              2>/dev/null > /tmp/initial_wakeTime       || echo "" > /tmp/initial_wakeTime
/usr/bin/defaults read "$DOMAIN" SUEnableAutomaticChecks 2>/dev/null > /tmp/initial_SUEnable    || echo "" > /tmp/initial_SUEnable
/usr/bin/defaults read "$DOMAIN" SUSendProfileInfo     2>/dev/null > /tmp/initial_SUSendProfile  || echo "" > /tmp/initial_SUSendProfile
/usr/bin/defaults read "$DOMAIN" lat                   2>/dev/null > /tmp/initial_lat            || echo "" > /tmp/initial_lat

# 4) Stamp task start AFTER baseline writes.
sleep 1
date +%s > /tmp/task_start_timestamp

echo "task_start_unix=$(cat /tmp/task_start_timestamp)"
echo "initial_wakeTime=$(cat /tmp/initial_wakeTime)"
echo "initial_SUEnableAutomaticChecks=$(cat /tmp/initial_SUEnable)"
echo "initial_SUSendProfileInfo=$(cat /tmp/initial_SUSendProfile)"

# 5) Take start screenshot.
/usr/sbin/screencapture -x /tmp/task_start.png 2>/dev/null || true

# 6) Launch Flux.
if ! pgrep -x Flux >/dev/null; then
  open -a Flux
fi
for i in $(seq 1 20); do
  /usr/bin/lsappinfo list 2>/dev/null | grep -qiE 'Flux\.app' && break
  sleep 1
done
sleep 2

echo "=== sync_wake_time_to_circadian_schedule setup complete ==="
