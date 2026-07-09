#!/bin/bash
# pre_task: prepare the org.herf.Flux preferences plist with a known
# challenge-baseline state, record initial values, then quit any running
# Flux process so the agent has a clean slate.
#
# Baseline state:
#   - wakeTime = 480  (8:00 AM — the value the agent must change to 360)
#   - lat / lng / place / SU* keys: as seeded by setup_flux.sh
#
# The script does NOT print the target value (360) — only the baseline (480),
# which the agent could also read by inspecting the plist itself, so there's
# no extra leakage (Anti-Pattern #10).
set -eu

DOMAIN="org.herf.Flux"
PLIST="$HOME/Library/Preferences/org.herf.Flux.plist"

echo "=== Setting up set_wake_time_to_6am ==="

# 1) Quit any running Flux so it can't auto-write back to the plist mid-task.
osascript -e 'tell application "Flux" to quit' 2>/dev/null || true
sleep 1
pkill -x Flux 2>/dev/null || true
sleep 1

# 2) Force the challenge baseline. We write the SAME values setup_flux.sh
#    already set, plus wakeTime=480 explicitly so the verifier's "agent
#    changed wakeTime from baseline" check has a stable starting point.
/usr/bin/defaults write "$DOMAIN" wakeTime -int 480
/usr/bin/defaults write "$DOMAIN" lat -float 40.4406
/usr/bin/defaults write "$DOMAIN" lng -float -79.9959
/usr/bin/defaults write "$DOMAIN" place -string "Pittsburgh, PA"
/usr/bin/defaults write "$DOMAIN" SUEnableAutomaticChecks -bool false
/usr/bin/defaults write "$DOMAIN" SUSendProfileInfo -bool false
/usr/bin/defaults write "$DOMAIN" SUHasLaunchedBefore -bool true

killall cfprefsd 2>/dev/null || true
sleep 1

# 3) Record baseline metadata for the verifier. Each `/tmp/initial_*` file is
#    consumed by export_result.sh.
/usr/bin/stat -f '%m' "$PLIST" 2>/dev/null > /tmp/initial_plist_mtime
/usr/bin/stat -f '%z' "$PLIST" 2>/dev/null > /tmp/initial_plist_size
/usr/bin/defaults read "$DOMAIN" wakeTime 2>/dev/null > /tmp/initial_wakeTime
/usr/bin/defaults read "$DOMAIN" lat       2>/dev/null > /tmp/initial_lat
/usr/bin/defaults read "$DOMAIN" lng       2>/dev/null > /tmp/initial_lng
/usr/bin/defaults read "$DOMAIN" SUSendProfileInfo 2>/dev/null > /tmp/initial_SUSendProfileInfo

# 4) Stamp task-start (Unix epoch) AFTER all baseline writes — so the
#    verifier's "plist mtime > task_start" check fires only when the agent
#    actually mutates the plist.
sleep 1   # ensure stat() resolution doesn't tie task_start to plist mtime
date +%s > /tmp/task_start_timestamp

echo "task_start_unix=$(cat /tmp/task_start_timestamp)"
echo "initial_wakeTime=$(cat /tmp/initial_wakeTime)"
echo "initial_plist_mtime=$(cat /tmp/initial_plist_mtime)"

# 5) Take a start-state screenshot for trajectory archiving.
/usr/sbin/screencapture -x /tmp/task_start.png 2>/dev/null || true

# 6) Launch Flux so the agent has access to the GUI as one possible
#    completion path. (The plist-direct path also works — the verifier is
#    end-state-based, so the launch is for UX, not correctness.)
if ! pgrep -x Flux >/dev/null; then
  open -a Flux
fi
for i in $(seq 1 20); do
  /usr/bin/lsappinfo list 2>/dev/null | grep -qiE 'Flux\.app' && break
  sleep 1
done
sleep 2

echo "=== set_wake_time_to_6am setup complete ==="
