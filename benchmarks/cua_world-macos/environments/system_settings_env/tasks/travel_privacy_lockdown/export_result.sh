#!/bin/bash
# post_task hook for travel_privacy_lockdown on system_settings_env.
#
# Reads appearance, screensaver security settings, and the top-left hot corner,
# then writes /tmp/travel_privacy_lockdown_result.json for the verifier.
# Anti-Pattern #12: python heredoc uses try/except, always writes valid JSON.
set -u   # NOT -e

echo "=== Exporting travel_privacy_lockdown results ==="

/usr/sbin/screencapture -x /tmp/task_end.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
echo "task_start_unix=$TASK_START"

killall cfprefsd 2>/dev/null || true
sleep 1

# ---------------------------------------------------------------------------
# Read all 5 settings.
# ---------------------------------------------------------------------------
APPEARANCE=$(defaults read -g AppleInterfaceStyle 2>/dev/null || echo "")
SS_IDLE=$(defaults read com.apple.screensaver idleTime 2>/dev/null || echo "")
SS_PASSWORD=$(defaults read com.apple.screensaver askForPassword 2>/dev/null || echo "")
SS_DELAY=$(defaults read com.apple.screensaver askForPasswordDelay 2>/dev/null || echo "")
TL_CORNER=$(defaults read com.apple.dock wvous-tl-corner 2>/dev/null || echo "")

echo "raw reads:"
echo "  AppleInterfaceStyle=${APPEARANCE}"
echo "  screensaver.idleTime=${SS_IDLE}"
echo "  screensaver.askForPassword=${SS_PASSWORD}"
echo "  screensaver.askForPasswordDelay=${SS_DELAY}"
echo "  wvous-tl-corner=${TL_CORNER}"

/usr/bin/python3 - "$TASK_START" \
    "$APPEARANCE" "$SS_IDLE" "$SS_PASSWORD" "$SS_DELAY" "$TL_CORNER" << 'PYEOF'
import json, sys

def to_int_or_none(s):
    s = str(s).strip()
    if not s:
        return None
    try:
        return int(float(s))
    except Exception:
        return None

def first_or_none(s):
    s = str(s).strip()
    return s if s else None

errors = []
try:
    task_start = int(sys.argv[1] or 0)
except Exception as e:
    task_start = 0
    errors.append(f"task_start: {e}")

appearance      = first_or_none(sys.argv[2])    # "Dark" or None (Light = absent)
ss_idle         = to_int_or_none(sys.argv[3])   # seconds until screensaver
ss_password     = to_int_or_none(sys.argv[4])   # 0=no password, 1=require password
ss_delay        = to_int_or_none(sys.argv[5])   # seconds of grace period after screensaver
tl_corner       = to_int_or_none(sys.argv[6])   # hot corner action code

result = {
    "task_start": task_start,
    "appearance": appearance,
    "screensaver_idle_time": ss_idle,
    "screensaver_ask_password": ss_password,
    "screensaver_password_delay": ss_delay,
    "hot_corner_top_left": tl_corner,
    "read_errors": errors,
}

try:
    with open("/tmp/travel_privacy_lockdown_result.json", "w") as f:
        json.dump(result, f, indent=2)
    print(json.dumps(result, indent=2))
except Exception as exc:
    fallback = {
        "task_start": task_start,
        "appearance": None, "screensaver_idle_time": None,
        "screensaver_ask_password": None, "screensaver_password_delay": None,
        "hot_corner_top_left": None,
        "read_errors": errors + [f"writeout: {exc}"],
    }
    try:
        with open("/tmp/travel_privacy_lockdown_result.json", "w") as f:
            json.dump(fallback, f, indent=2)
    except Exception:
        pass
    print(json.dumps(fallback, indent=2))
PYEOF

echo "=== Export complete ==="
