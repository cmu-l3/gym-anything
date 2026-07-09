#!/bin/bash
# post_task hook for family_accessibility_elderly on system_settings_env.
#
# Reads all 6 target accessibility settings from com.apple.universalaccess
# and writes /tmp/family_accessibility_elderly_result.json for the verifier.
# Anti-Pattern #12: python heredoc uses try/except and always writes valid JSON.
set -u   # NOT -e — partial reads must keep going

echo "=== Exporting family_accessibility_elderly results ==="

/usr/sbin/screencapture -x /tmp/task_end.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
echo "task_start_unix=$TASK_START"

# Flush cfprefsd before reading so agent's UI changes are visible to defaults.
killall cfprefsd 2>/dev/null || true
sleep 1

# ---------------------------------------------------------------------------
# Read all 6 accessibility settings.
# Absent key → empty string, which Python converts to None/baseline.
# ---------------------------------------------------------------------------
INCREASE_CONTRAST=$(defaults read com.apple.universalaccess increaseContrast 2>/dev/null || echo "")
REDUCE_TRANSPARENCY=$(defaults read com.apple.universalaccess reduceTransparency 2>/dev/null || echo "")
CURSOR_SIZE=$(defaults read com.apple.universalaccess cursorSize 2>/dev/null || echo "")
SCROLL_ZOOM=$(defaults read com.apple.universalaccess closeViewScrollWheelToggle 2>/dev/null || echo "")
STICKY_KEY=$(defaults read com.apple.universalaccess stickyKey 2>/dev/null || echo "")
SLOW_KEY=$(defaults read com.apple.universalaccess slowKey 2>/dev/null || echo "")

echo "raw reads:"
echo "  increaseContrast=${INCREASE_CONTRAST}"
echo "  reduceTransparency=${REDUCE_TRANSPARENCY}"
echo "  cursorSize=${CURSOR_SIZE}"
echo "  closeViewScrollWheelToggle=${SCROLL_ZOOM}"
echo "  stickyKey=${STICKY_KEY}"
echo "  slowKey=${SLOW_KEY}"

/usr/bin/python3 - "$TASK_START" \
    "$INCREASE_CONTRAST" "$REDUCE_TRANSPARENCY" "$CURSOR_SIZE" \
    "$SCROLL_ZOOM" "$STICKY_KEY" "$SLOW_KEY" << 'PYEOF'
import json, sys

def to_bool(s):
    """defaults read prints 1 for true, 0 for false for bool keys."""
    return str(s).strip() == "1"

def to_float_or_none(s):
    s = str(s).strip()
    if not s:
        return None
    try:
        return float(s)
    except Exception:
        return None

errors = []
try:
    task_start = int(sys.argv[1] or 0)
except Exception as e:
    task_start = 0
    errors.append(f"task_start: {e}")

increase_contrast    = to_bool(sys.argv[2])
reduce_transparency  = to_bool(sys.argv[3])
cursor_size          = to_float_or_none(sys.argv[4])
scroll_zoom          = to_bool(sys.argv[5])
sticky_key           = to_bool(sys.argv[6])
slow_key             = to_bool(sys.argv[7])

result = {
    "task_start": task_start,
    "increase_contrast": increase_contrast,
    "reduce_transparency": reduce_transparency,
    "cursor_size": cursor_size,
    "scroll_wheel_zoom": scroll_zoom,
    "sticky_key": sticky_key,
    "slow_key": slow_key,
    "read_errors": errors,
}

try:
    with open("/tmp/family_accessibility_elderly_result.json", "w") as f:
        json.dump(result, f, indent=2)
    print(json.dumps(result, indent=2))
except Exception as exc:
    fallback = {
        "task_start": task_start,
        "increase_contrast": False, "reduce_transparency": False,
        "cursor_size": None, "scroll_wheel_zoom": False,
        "sticky_key": False, "slow_key": False,
        "read_errors": errors + [f"writeout: {exc}"],
    }
    try:
        with open("/tmp/family_accessibility_elderly_result.json", "w") as f:
            json.dump(fallback, f, indent=2)
    except Exception:
        pass
    print(json.dumps(fallback, indent=2))
PYEOF

echo "=== Export complete ==="
