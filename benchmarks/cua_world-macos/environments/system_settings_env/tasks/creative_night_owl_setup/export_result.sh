#!/bin/bash
# post_task hook for creative_night_owl_setup on system_settings_env.
#
# Reads keyboard repeat settings and hot corner values, then writes
# /tmp/creative_night_owl_setup_result.json for the verifier.
# Anti-Pattern #12: python heredoc uses try/except, always writes valid JSON.
set -u   # NOT -e — partial reads must keep going

echo "=== Exporting creative_night_owl_setup results ==="

/usr/sbin/screencapture -x /tmp/task_end.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
echo "task_start_unix=$TASK_START"

killall cfprefsd 2>/dev/null || true
sleep 1

# ---------------------------------------------------------------------------
# Read all 5 settings.
# ---------------------------------------------------------------------------
REDUCE_MOTION=$(defaults read -g AppleReduceMotion 2>/dev/null || echo "")
KEY_REPEAT=$(defaults read -g KeyRepeat 2>/dev/null || echo "")
INITIAL_KEY_REPEAT=$(defaults read -g InitialKeyRepeat 2>/dev/null || echo "")
BL_CORNER=$(defaults read com.apple.dock wvous-bl-corner 2>/dev/null || echo "")
TR_CORNER=$(defaults read com.apple.dock wvous-tr-corner 2>/dev/null || echo "")

echo "raw reads:"
echo "  AppleReduceMotion=${REDUCE_MOTION}"
echo "  KeyRepeat=${KEY_REPEAT}"
echo "  InitialKeyRepeat=${INITIAL_KEY_REPEAT}"
echo "  wvous-bl-corner=${BL_CORNER}"
echo "  wvous-tr-corner=${TR_CORNER}"

/usr/bin/python3 - "$TASK_START" \
    "$REDUCE_MOTION" "$KEY_REPEAT" "$INITIAL_KEY_REPEAT" \
    "$BL_CORNER" "$TR_CORNER" << 'PYEOF'
import json, sys

def to_bool(s):
    return str(s).strip() == "1"

def to_int_or_none(s):
    s = str(s).strip()
    if not s:
        return None
    try:
        return int(s)
    except Exception:
        return None

errors = []
try:
    task_start = int(sys.argv[1] or 0)
except Exception as e:
    task_start = 0
    errors.append(f"task_start: {e}")

reduce_motion      = to_bool(sys.argv[2])
key_repeat         = to_int_or_none(sys.argv[3])
initial_key_repeat = to_int_or_none(sys.argv[4])
bl_corner          = to_int_or_none(sys.argv[5])
tr_corner          = to_int_or_none(sys.argv[6])

result = {
    "task_start": task_start,
    "reduce_motion": reduce_motion,
    "key_repeat": key_repeat,
    "initial_key_repeat": initial_key_repeat,
    "hot_corner_bottom_left": bl_corner,
    "hot_corner_top_right": tr_corner,
    "read_errors": errors,
}

try:
    with open("/tmp/creative_night_owl_setup_result.json", "w") as f:
        json.dump(result, f, indent=2)
    print(json.dumps(result, indent=2))
except Exception as exc:
    fallback = {
        "task_start": task_start,
        "reduce_motion": False, "key_repeat": None,
        "initial_key_repeat": None, "hot_corner_bottom_left": None,
        "hot_corner_top_right": None,
        "read_errors": errors + [f"writeout: {exc}"],
    }
    try:
        with open("/tmp/creative_night_owl_setup_result.json", "w") as f:
            json.dump(fallback, f, indent=2)
    except Exception:
        pass
    print(json.dumps(fallback, indent=2))
PYEOF

echo "=== Export complete ==="
