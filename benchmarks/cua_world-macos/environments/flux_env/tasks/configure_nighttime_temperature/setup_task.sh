#!/bin/bash
# pre_task: seed a clean challenge baseline and capture the initial full plist
# key-value dump so the verifier can diff before/after to find the Bedtime K key.
set -eu

DOMAIN="org.herf.Flux"
PLIST="$HOME/Library/Preferences/org.herf.Flux.plist"

echo "=== Setting up configure_nighttime_temperature ==="

# 1) Quit any running Flux.
osascript -e 'tell application "Flux" to quit' 2>/dev/null || true
sleep 1
pkill -x Flux 2>/dev/null || true
sleep 1

# 2) Write clean baseline (only confirmed keys — no K-temperature seeding
#    so the agent must discover the K key via the UI or plist probing).
/usr/bin/defaults write "$DOMAIN" wakeTime               -int   480
/usr/bin/defaults write "$DOMAIN" SUEnableAutomaticChecks -bool  false
/usr/bin/defaults write "$DOMAIN" SUSendProfileInfo       -bool  false
/usr/bin/defaults write "$DOMAIN" SUHasLaunchedBefore     -bool  true
/usr/bin/defaults write "$DOMAIN" lat    -float  40.4406
/usr/bin/defaults write "$DOMAIN" lng    -float -79.9959
/usr/bin/defaults write "$DOMAIN" place  -string "Pittsburgh, PA"

killall cfprefsd 2>/dev/null || true
sleep 1

# 3) Capture the initial full plist KV dict (key->value map, all types preserved).
#    The verifier diffs this against the post-task dump to find the Bedtime K key
#    without needing to know its name in advance.
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
    result = {k: _serial(v) for k, v in data.items()}
    with open(sys.argv[2], "w") as out:
        json.dump(result, out)
    print(f"initial plist captured: {len(result)} keys → {sys.argv[2]}")
except Exception as e:
    with open(sys.argv[2], "w") as out:
        json.dump({"_error": str(e)}, out)
    print(f"ERROR capturing initial plist: {e}")
PYEOF

# 4) Record scalar baseline values for anti-gaming checks.
/usr/bin/defaults read "$DOMAIN" wakeTime    2>/dev/null > /tmp/initial_wakeTime || echo "" > /tmp/initial_wakeTime
/usr/bin/defaults read "$DOMAIN" SUSendProfileInfo 2>/dev/null > /tmp/initial_SUSendProfile || echo "" > /tmp/initial_SUSendProfile
/usr/bin/stat -f '%m' "$PLIST" 2>/dev/null > /tmp/initial_plist_mtime || echo "0" > /tmp/initial_plist_mtime

# 5) Stamp task start.
sleep 1
date +%s > /tmp/task_start_timestamp

echo "task_start=$(cat /tmp/task_start_timestamp)  initial_wakeTime=$(cat /tmp/initial_wakeTime)"

# 6) Screenshot.
/usr/sbin/screencapture -x /tmp/task_start.png 2>/dev/null || true

# 7) Launch Flux.
if ! pgrep -x Flux >/dev/null; then
  open -a Flux
fi
for i in $(seq 1 20); do
  /usr/bin/lsappinfo list 2>/dev/null | grep -qiE 'Flux\.app' && break
  sleep 1
done
sleep 2

echo "=== configure_nighttime_temperature setup complete ==="
