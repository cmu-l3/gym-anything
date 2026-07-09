#!/bin/bash
# post_task: export final plist state including full KV dump for diff-based
# Bedtime K detection in verifier.py.
set -u

echo "=== Exporting configure_nighttime_temperature results ==="

DOMAIN="org.herf.Flux"
PLIST="$HOME/Library/Preferences/org.herf.Flux.plist"

/usr/sbin/screencapture -x /tmp/task_end.png 2>/dev/null || true

# Flush all writes to disk.
osascript -e 'tell application "Flux" to quit' 2>/dev/null || true
sleep 2
pkill -x Flux 2>/dev/null || true
sleep 1
killall cfprefsd 2>/dev/null || true
sleep 1

TASK_START=$(cat /tmp/task_start_timestamp  2>/dev/null || echo "0")
INITIAL_WT=$(cat /tmp/initial_wakeTime       2>/dev/null || echo "")
INITIAL_SUS=$(cat /tmp/initial_SUSendProfile 2>/dev/null || echo "")
INITIAL_MTIME=$(cat /tmp/initial_plist_mtime 2>/dev/null || echo "0")

PLIST_EXISTS=0
PLIST_MTIME=0
PLIST_TOUCHED=0
if [ -f "$PLIST" ]; then
  PLIST_EXISTS=1
  PLIST_MTIME=$(/usr/bin/stat -f '%m' "$PLIST" 2>/dev/null || echo "0")
  if [ "$PLIST_MTIME" -gt "$TASK_START" ] 2>/dev/null; then
    PLIST_TOUCHED=1
  fi
fi

FINAL_WT=$(/usr/bin/defaults read "$DOMAIN" wakeTime          2>/dev/null || echo "")
FINAL_SUS=$(/usr/bin/defaults read "$DOMAIN" SUSendProfileInfo 2>/dev/null || echo "")

# Capture full final plist KV dict to a temp file for diff-based K detection.
/usr/bin/python3 - "$PLIST" /tmp/final_plist_kv.json << 'PYEOF'
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
    print(f"final plist: {len(out)} keys")
except Exception as e:
    with open(sys.argv[2], "w") as f:
        json.dump({"_error": str(e)}, f)
    print(f"ERROR: {e}")
PYEOF

echo "plist_exists=$PLIST_EXISTS plist_touched=$PLIST_TOUCHED"
echo "final_wakeTime=$FINAL_WT final_SUSendProfileInfo=$FINAL_SUS"

rm -f /tmp/configure_nighttime_temperature_result.json

# Build result JSON from file paths + scalar fields.
/usr/bin/python3 - \
  "$TASK_START" "$INITIAL_WT" "$FINAL_WT" \
  "$INITIAL_SUS" "$FINAL_SUS" \
  "$INITIAL_MTIME" "$PLIST_MTIME" \
  "$PLIST_EXISTS" "$PLIST_TOUCHED" \
  /tmp/initial_plist_kv.json /tmp/final_plist_kv.json << 'PYEOF'
import json, sys

def _int(x):
    try: return int(x)
    except Exception: return None
def _bool(x):
    if str(x).strip().lower() in ("0","false","no"): return False
    if str(x).strip().lower() in ("1","true","yes"):  return True
    return None
def _load_kv(path):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception as e:
        return {"_error": str(e)}

result = {
    "task": "configure_nighttime_temperature",
    "task_start":                     int(sys.argv[1] or 0),
    "plist_exists":                   bool(int(sys.argv[8])),
    "plist_touched_after_task_start": bool(int(sys.argv[9])),
    "initial_plist_mtime":            _int(sys.argv[6]),
    "final_plist_mtime":              _int(sys.argv[7]),
    "initial_wakeTime":               _int(sys.argv[2]),
    "final_wakeTime":                 _int(sys.argv[3]),
    "initial_SUSendProfileInfo":      _bool(sys.argv[4]),
    "final_SUSendProfileInfo":        _bool(sys.argv[5]),
    "initial_plist_kv":               _load_kv(sys.argv[10]),
    "final_plist_kv":                 _load_kv(sys.argv[11]),
}
with open("/tmp/configure_nighttime_temperature_result.json", "w") as f:
    json.dump(result, f, indent=2)
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="
