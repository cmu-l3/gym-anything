#!/bin/bash
# pre_task: seed challenge baseline (wakeTime=600, SUEnableAutomaticChecks=true)
# and capture initial full plist KV dump for K-temperature diff detection.
set -eu

DOMAIN="org.herf.Flux"
PLIST="$HOME/Library/Preferences/org.herf.Flux.plist"

echo "=== Setting up configure_complete_sleep_profile ==="

osascript -e 'tell application "Flux" to quit' 2>/dev/null || true
sleep 1
pkill -x Flux 2>/dev/null || true
sleep 1

# Seed all three baseline values (two need fixing, one preserved).
/usr/bin/defaults write "$DOMAIN" wakeTime                -int   600
/usr/bin/defaults write "$DOMAIN" SUEnableAutomaticChecks  -bool  true
/usr/bin/defaults write "$DOMAIN" SUSendProfileInfo        -bool  false
/usr/bin/defaults write "$DOMAIN" SUHasLaunchedBefore      -bool  true
/usr/bin/defaults write "$DOMAIN" lat    -float  40.4406
/usr/bin/defaults write "$DOMAIN" lng    -float -79.9959
/usr/bin/defaults write "$DOMAIN" place  -string "Pittsburgh, PA"

killall cfprefsd 2>/dev/null || true
sleep 1

# Capture initial full KV dump for K-temp diff detection.
/usr/bin/python3 - "$PLIST" /tmp/initial_plist_kv.json << 'PYEOF'
import json, plistlib, sys

def _serial(v):
    if isinstance(v, bool): return bool(v)
    if isinstance(v, int):  return int(v)
    if isinstance(v, float):return float(v)
    return str(v)

try:
    with open(sys.argv[1], "rb") as f:
        data = plistlib.load(f)
    out = {k: _serial(v) for k, v in data.items()}
    with open(sys.argv[2], "w") as f:
        json.dump(out, f)
    print(f"initial plist KV: {len(out)} keys")
except Exception as e:
    with open(sys.argv[2], "w") as f:
        json.dump({"_error": str(e)}, f)
    print(f"ERROR: {e}")
PYEOF

/usr/bin/stat -f '%m' "$PLIST" 2>/dev/null > /tmp/initial_plist_mtime  || echo "0" > /tmp/initial_plist_mtime
/usr/bin/defaults read "$DOMAIN" wakeTime               2>/dev/null > /tmp/initial_wakeTime  || echo "" > /tmp/initial_wakeTime
/usr/bin/defaults read "$DOMAIN" SUEnableAutomaticChecks 2>/dev/null > /tmp/initial_SUEnable || echo "" > /tmp/initial_SUEnable
/usr/bin/defaults read "$DOMAIN" SUSendProfileInfo      2>/dev/null > /tmp/initial_SUSend    || echo "" > /tmp/initial_SUSend

sleep 1
date +%s > /tmp/task_start_timestamp

echo "task_start=$(cat /tmp/task_start_timestamp)"
echo "initial_wakeTime=$(cat /tmp/initial_wakeTime)  initial_SUEnable=$(cat /tmp/initial_SUEnable)"

/usr/sbin/screencapture -x /tmp/task_start.png 2>/dev/null || true

if ! pgrep -x Flux >/dev/null; then
  open -a Flux
fi
for i in $(seq 1 20); do
  /usr/bin/lsappinfo list 2>/dev/null | grep -qiE 'Flux\.app' && break
  sleep 1
done
sleep 2

echo "=== configure_complete_sleep_profile setup complete ==="
