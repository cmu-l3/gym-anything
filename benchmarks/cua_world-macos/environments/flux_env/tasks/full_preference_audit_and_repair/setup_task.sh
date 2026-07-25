#!/bin/bash
# pre_task: seed three drifted values the agent must audit and repair:
#   wakeTime = 1440  (midnight — wrong; should be 480 = 8:00 AM)
#   SUEnableAutomaticChecks = true  (wrong; should be false)
#   SUSendProfileInfo = true        (wrong; should be false)
set -eu

DOMAIN="org.herf.Flux"
PLIST="$HOME/Library/Preferences/org.herf.Flux.plist"

echo "=== Setting up full_preference_audit_and_repair ==="

osascript -e 'tell application "Flux" to quit' 2>/dev/null || true
sleep 1
pkill -x Flux 2>/dev/null || true
sleep 1

# Write three drifted (wrong) values.
# NOTE: 1440 = midnight is normalized to 1425 by Flux on launch; use 660 (11:00 AM)
# which is within the valid stepper range and won't be overwritten by Flux.
/usr/bin/defaults write "$DOMAIN" wakeTime                -int   660
/usr/bin/defaults write "$DOMAIN" SUEnableAutomaticChecks  -bool  true
/usr/bin/defaults write "$DOMAIN" SUSendProfileInfo        -bool  true
# Keep these correct (preserved, must not be changed).
/usr/bin/defaults write "$DOMAIN" SUHasLaunchedBefore      -bool  true
/usr/bin/defaults write "$DOMAIN" lat    -float  40.4406
/usr/bin/defaults write "$DOMAIN" lng    -float -79.9959
/usr/bin/defaults write "$DOMAIN" place  -string "Pittsburgh, PA"

killall cfprefsd 2>/dev/null || true
sleep 1

/usr/bin/stat -f '%m' "$PLIST" 2>/dev/null > /tmp/initial_plist_mtime  || echo "0" > /tmp/initial_plist_mtime
/usr/bin/defaults read "$DOMAIN" wakeTime               2>/dev/null > /tmp/initial_wakeTime   || echo "" > /tmp/initial_wakeTime
/usr/bin/defaults read "$DOMAIN" SUEnableAutomaticChecks 2>/dev/null > /tmp/initial_SUEnable  || echo "" > /tmp/initial_SUEnable
/usr/bin/defaults read "$DOMAIN" SUSendProfileInfo      2>/dev/null > /tmp/initial_SUSend     || echo "" > /tmp/initial_SUSend
/usr/bin/defaults read "$DOMAIN" lat                    2>/dev/null > /tmp/initial_lat        || echo "" > /tmp/initial_lat

sleep 1
date +%s > /tmp/task_start_timestamp

echo "task_start=$(cat /tmp/task_start_timestamp)"
echo "drifted: wakeTime=$(cat /tmp/initial_wakeTime) SUEnable=$(cat /tmp/initial_SUEnable) SUSend=$(cat /tmp/initial_SUSend)"

/usr/sbin/screencapture -x /tmp/task_start.png 2>/dev/null || true

if ! pgrep -x Flux >/dev/null; then
  open -a Flux
fi
for i in $(seq 1 20); do
  /usr/bin/lsappinfo list 2>/dev/null | grep -qiE 'Flux\.app' && break
  sleep 1
done
sleep 2

echo "=== full_preference_audit_and_repair setup complete ==="
