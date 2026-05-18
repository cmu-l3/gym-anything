#!/bin/bash
# post_task: export plist state for repair_wrong_wake_time_encoding.
set -u

echo "=== Exporting repair_wrong_wake_time_encoding results ==="

DOMAIN="org.herf.Flux"
PLIST="$HOME/Library/Preferences/org.herf.Flux.plist"

/usr/sbin/screencapture -x /tmp/task_end.png 2>/dev/null || true

osascript -e 'tell application "Flux" to quit' 2>/dev/null || true
sleep 2
pkill -x Flux 2>/dev/null || true
sleep 1
killall cfprefsd 2>/dev/null || true
sleep 1

TASK_START=$(cat /tmp/task_start_timestamp  2>/dev/null || echo "0")
INITIAL_WT=$(cat /tmp/initial_wakeTime       2>/dev/null || echo "")
INITIAL_SUE=$(cat /tmp/initial_SUEnable      2>/dev/null || echo "")
INITIAL_SUS=$(cat /tmp/initial_SUSend        2>/dev/null || echo "")
INITIAL_LAT=$(cat /tmp/initial_lat           2>/dev/null || echo "")
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

FINAL_WT=$(/usr/bin/defaults read "$DOMAIN" wakeTime               2>/dev/null || echo "")
FINAL_SUE=$(/usr/bin/defaults read "$DOMAIN" SUEnableAutomaticChecks 2>/dev/null || echo "")
FINAL_SUS=$(/usr/bin/defaults read "$DOMAIN" SUSendProfileInfo      2>/dev/null || echo "")
FINAL_LAT=$(/usr/bin/defaults read "$DOMAIN" lat                    2>/dev/null || echo "")

ALL_KEYS_JSON=$(/usr/bin/python3 - "$PLIST" << 'PYEOF'
import json, plistlib, sys
try:
    with open(sys.argv[1], "rb") as f:
        data = plistlib.load(f)
    print(json.dumps(sorted(str(k) for k in data.keys())))
except Exception as e:
    print(json.dumps({"error": str(e)}))
PYEOF
)

echo "final_wakeTime=$FINAL_WT (target: 480)  plist_touched=$PLIST_TOUCHED"

rm -f /tmp/repair_wrong_wake_time_encoding_result.json

/usr/bin/python3 - \
  "$TASK_START" "$INITIAL_WT" "$FINAL_WT" \
  "$INITIAL_SUE" "$FINAL_SUE" \
  "$INITIAL_SUS" "$FINAL_SUS" \
  "$INITIAL_LAT" "$FINAL_LAT" \
  "$INITIAL_MTIME" "$PLIST_MTIME" \
  "$PLIST_EXISTS" "$PLIST_TOUCHED" "$ALL_KEYS_JSON" << 'PYEOF'
import json, sys

def _int(x):
    try: return int(x)
    except Exception: return None
def _float(x):
    try: return float(x)
    except Exception: return None
def _bool(x):
    if str(x).strip().lower() in ("0","false","no"): return False
    if str(x).strip().lower() in ("1","true","yes"):  return True
    return None

try:
    all_keys = json.loads(sys.argv[14])
    parse_error = isinstance(all_keys, dict) and "error" in all_keys
    if parse_error: all_keys = []
except Exception:
    all_keys = []; parse_error = True

result = {
    "task": "repair_wrong_wake_time_encoding",
    "task_start":                     int(sys.argv[1] or 0),
    "plist_exists":                   bool(int(sys.argv[12])),
    "plist_touched_after_task_start": bool(int(sys.argv[13])),
    "plist_parse_error":              parse_error,
    "initial_plist_mtime":            _int(sys.argv[10]),
    "final_plist_mtime":              _int(sys.argv[11]),
    "initial_wakeTime":               _int(sys.argv[2]),
    "final_wakeTime":                 _int(sys.argv[3]),
    "initial_SUEnableAutomaticChecks":_bool(sys.argv[4]),
    "final_SUEnableAutomaticChecks":  _bool(sys.argv[5]),
    "initial_SUSendProfileInfo":      _bool(sys.argv[6]),
    "final_SUSendProfileInfo":        _bool(sys.argv[7]),
    "initial_lat":                    _float(sys.argv[8]),
    "final_lat":                      _float(sys.argv[9]),
    "final_plist_keys":               all_keys,
}
with open("/tmp/repair_wrong_wake_time_encoding_result.json", "w") as f:
    json.dump(result, f, indent=2)
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="
