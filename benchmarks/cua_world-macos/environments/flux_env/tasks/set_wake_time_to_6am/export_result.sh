#!/bin/bash
# post_task: read the final state of org.herf.Flux's plist, compare to
# baselines stored in /tmp by setup_task.sh, and write a result JSON the
# verifier reads via env_info["copy_from_env"].
#
# Anti-pattern #12 (Python heredoc stdout): every embedded Python block has
# try/except + safe defaults, so the verifier always reads valid JSON.
#
# NOTE: we do NOT use `set -e` — individual stage failures must not abort
# the script before the result JSON is written.
set -u

echo "=== Exporting set_wake_time_to_6am results ==="

DOMAIN="org.herf.Flux"
PLIST="$HOME/Library/Preferences/org.herf.Flux.plist"

/usr/sbin/screencapture -x /tmp/task_end.png 2>/dev/null || true

# Quit Flux so cfprefsd flushes; this guarantees `defaults read` reflects
# any in-memory mutations f.lux made during the task window.
osascript -e 'tell application "Flux" to quit' 2>/dev/null || true
sleep 2
pkill -x Flux 2>/dev/null || true
sleep 1
killall cfprefsd 2>/dev/null || true
sleep 1

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
INITIAL_WAKETIME=$(cat /tmp/initial_wakeTime 2>/dev/null || echo "")
INITIAL_LAT=$(cat /tmp/initial_lat 2>/dev/null || echo "")
INITIAL_LNG=$(cat /tmp/initial_lng 2>/dev/null || echo "")
INITIAL_SUSEND=$(cat /tmp/initial_SUSendProfileInfo 2>/dev/null || echo "")
INITIAL_MTIME=$(cat /tmp/initial_plist_mtime 2>/dev/null || echo "0")

PLIST_EXISTS=0
PLIST_MTIME=0
PLIST_SIZE=0
PLIST_TOUCHED=0
if [ -f "$PLIST" ]; then
  PLIST_EXISTS=1
  PLIST_MTIME=$(/usr/bin/stat -f '%m' "$PLIST" 2>/dev/null || echo "0")
  PLIST_SIZE=$(/usr/bin/stat -f '%z' "$PLIST" 2>/dev/null || echo "0")
  # Touched-by-agent iff plist mtime > task_start_timestamp.
  if [ "$PLIST_MTIME" -gt "$TASK_START" ] 2>/dev/null; then
    PLIST_TOUCHED=1
  fi
fi

FINAL_WAKETIME=$(/usr/bin/defaults read "$DOMAIN" wakeTime 2>/dev/null || echo "")
FINAL_LAT=$(/usr/bin/defaults read "$DOMAIN" lat 2>/dev/null || echo "")
FINAL_LNG=$(/usr/bin/defaults read "$DOMAIN" lng 2>/dev/null || echo "")
FINAL_SUSEND=$(/usr/bin/defaults read "$DOMAIN" SUSendProfileInfo 2>/dev/null || echo "")

# Also pull the full plist key list (used by verifier's anti-gaming gate
# — detects keys the agent added unrelated to wakeTime).
ALL_KEYS_JSON=$(/usr/bin/python3 - "$PLIST" << 'PYEOF'
import json, plistlib, sys
try:
    with open(sys.argv[1], "rb") as f:
        data = plistlib.load(f)
    keys = sorted(str(k) for k in data.keys())
    print(json.dumps(keys))
except Exception as e:
    print(json.dumps({"error": f"{type(e).__name__}: {e}"}))
PYEOF
)

echo "plist_exists=$PLIST_EXISTS plist_touched=$PLIST_TOUCHED"
echo "final_wakeTime=$FINAL_WAKETIME initial_wakeTime=$INITIAL_WAKETIME"
echo "final_lat=$FINAL_LAT  final_SUSendProfileInfo=$FINAL_SUSEND"

# Stitch the result JSON. One Python call so quoting is unambiguous.
/usr/bin/python3 - "$TASK_START" "$INITIAL_WAKETIME" "$FINAL_WAKETIME" \
                   "$INITIAL_LAT" "$FINAL_LAT" \
                   "$INITIAL_LNG" "$FINAL_LNG" \
                   "$INITIAL_SUSEND" "$FINAL_SUSEND" \
                   "$INITIAL_MTIME" "$PLIST_MTIME" "$PLIST_SIZE" \
                   "$PLIST_EXISTS" "$PLIST_TOUCHED" "$ALL_KEYS_JSON" << 'PYEOF'
import json, sys

def _intornone(x):
    try:
        return int(x)
    except Exception:
        return None

def _floatornone(x):
    try:
        return float(x)
    except Exception:
        return None

def _boolornone(x):
    if x in ("0", "false", "False", "FALSE", "no", "NO"):
        return False
    if x in ("1", "true", "True", "TRUE", "yes", "YES"):
        return True
    return None

# Parse all-keys list from the embedded probe (may be a list or {"error": ...})
try:
    all_keys = json.loads(sys.argv[15])
    if isinstance(all_keys, dict) and "error" in all_keys:
        all_keys = []
        plist_parse_error = True
    else:
        plist_parse_error = False
except Exception:
    all_keys = []
    plist_parse_error = True

result = {
    "task": "set_wake_time_to_6am",
    "task_start": int(sys.argv[1] or 0),
    "plist_exists": bool(int(sys.argv[13])),
    "plist_touched_after_task_start": bool(int(sys.argv[14])),
    "plist_parse_error": plist_parse_error,
    "initial_plist_mtime": int(sys.argv[10] or 0),
    "final_plist_mtime": int(sys.argv[11] or 0),
    "final_plist_size_bytes": int(sys.argv[12] or 0),
    "initial_wakeTime": _intornone(sys.argv[2]),
    "final_wakeTime": _intornone(sys.argv[3]),
    "initial_lat": _floatornone(sys.argv[4]),
    "final_lat": _floatornone(sys.argv[5]),
    "initial_lng": _floatornone(sys.argv[6]),
    "final_lng": _floatornone(sys.argv[7]),
    "initial_SUSendProfileInfo": _boolornone(sys.argv[8]),
    "final_SUSendProfileInfo": _boolornone(sys.argv[9]),
    "final_plist_keys": all_keys,
}
with open("/tmp/set_wake_time_to_6am_result.json", "w") as f:
    json.dump(result, f, indent=2)
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="
