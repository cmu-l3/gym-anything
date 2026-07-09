#!/bin/bash
# pre_task: seed wakeTime = 28800 (wrong: seconds from midnight for 8 AM).
# The correct value is 480 (minutes from midnight for 8:00 AM).
set -eu

DOMAIN="org.herf.Flux"
PLIST="$HOME/Library/Preferences/org.herf.Flux.plist"

echo "=== Setting up repair_wrong_wake_time_encoding ==="

osascript -e 'tell application "Flux" to quit' 2>/dev/null || true
sleep 1
pkill -x Flux 2>/dev/null || true
sleep 1

# Seed the bad value (28800 = seconds, not minutes) plus normal other keys.
/usr/bin/defaults write "$DOMAIN" wakeTime               -int   28800
/usr/bin/defaults write "$DOMAIN" SUEnableAutomaticChecks -bool  false
/usr/bin/defaults write "$DOMAIN" SUSendProfileInfo       -bool  false
/usr/bin/defaults write "$DOMAIN" SUHasLaunchedBefore     -bool  true
/usr/bin/defaults write "$DOMAIN" lat    -float  40.4406
/usr/bin/defaults write "$DOMAIN" lng    -float -79.9959
/usr/bin/defaults write "$DOMAIN" place  -string "Pittsburgh, PA"

killall cfprefsd 2>/dev/null || true
sleep 1

/usr/bin/stat -f '%m' "$PLIST" 2>/dev/null > /tmp/initial_plist_mtime  || echo "0" > /tmp/initial_plist_mtime
/usr/bin/defaults read "$DOMAIN" wakeTime              2>/dev/null > /tmp/initial_wakeTime   || echo "" > /tmp/initial_wakeTime
/usr/bin/defaults read "$DOMAIN" SUEnableAutomaticChecks 2>/dev/null > /tmp/initial_SUEnable || echo "" > /tmp/initial_SUEnable
/usr/bin/defaults read "$DOMAIN" SUSendProfileInfo     2>/dev/null > /tmp/initial_SUSend     || echo "" > /tmp/initial_SUSend
/usr/bin/defaults read "$DOMAIN" lat                   2>/dev/null > /tmp/initial_lat        || echo "" > /tmp/initial_lat

sleep 1
date +%s > /tmp/task_start_timestamp

echo "task_start=$(cat /tmp/task_start_timestamp)"
echo "initial_wakeTime=$(cat /tmp/initial_wakeTime)  (28800 = wrong encoding — should be 480)"

/usr/sbin/screencapture -x /tmp/task_start.png 2>/dev/null || true

# Do NOT launch Flux here — the bad value would be immediately overwritten
# by Flux's own normalization logic on startup. Leave the plist as-is so
# the agent encounters wakeTime=28800 directly in the plist.

echo "=== repair_wrong_wake_time_encoding setup complete ==="
