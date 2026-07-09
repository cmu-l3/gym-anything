#!/bin/bash
# post_task hook for home_office_productivity on system_settings_env.
#
# Reads appearance auto-switch, scroll bars, UI sounds, Dock recent apps,
# and minimize effect, then writes /tmp/home_office_productivity_result.json.
# Anti-Pattern #12: python heredoc uses try/except, always writes valid JSON.
set -u   # NOT -e

echo "=== Exporting home_office_productivity results ==="

/usr/sbin/screencapture -x /tmp/task_end.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
echo "task_start_unix=$TASK_START"

killall cfprefsd 2>/dev/null || true
sleep 1

# ---------------------------------------------------------------------------
# Read all 5 settings.
# ---------------------------------------------------------------------------
AUTO_APPEARANCE=$(defaults read -g AppleInterfaceStyleSwitchesAutomatically 2>/dev/null || echo "")
SCROLLBARS=$(defaults read -g AppleShowScrollBars 2>/dev/null || echo "")
BEEP_FEEDBACK=$(defaults read -g com.apple.sound.beep.feedback 2>/dev/null || echo "")
SHOW_RECENTS=$(defaults read com.apple.dock show-recents 2>/dev/null || echo "")
MIN_EFFECT=$(defaults read com.apple.dock mineffect 2>/dev/null || echo "")

echo "raw reads:"
echo "  AppleInterfaceStyleSwitchesAutomatically=${AUTO_APPEARANCE}"
echo "  AppleShowScrollBars=${SCROLLBARS}"
echo "  com.apple.sound.beep.feedback=${BEEP_FEEDBACK}"
echo "  dock.show-recents=${SHOW_RECENTS}"
echo "  dock.mineffect=${MIN_EFFECT}"

/usr/bin/python3 - "$TASK_START" \
    "$AUTO_APPEARANCE" "$SCROLLBARS" "$BEEP_FEEDBACK" \
    "$SHOW_RECENTS" "$MIN_EFFECT" << 'PYEOF'
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

def first_or_none(s):
    s = str(s).strip()
    return s if s else None

errors = []
try:
    task_start = int(sys.argv[1] or 0)
except Exception as e:
    task_start = 0
    errors.append(f"task_start: {e}")

auto_appearance = to_bool(sys.argv[2])
scrollbars      = first_or_none(sys.argv[3])   # "Always", "Automatic", "WhenScrolling"
beep_feedback   = to_int_or_none(sys.argv[4])  # 1=sounds on, 0=sounds off
show_recents    = to_bool(sys.argv[5])          # true=show recent apps in Dock
min_effect      = first_or_none(sys.argv[6])   # "genie" or "scale"

result = {
    "task_start": task_start,
    "auto_appearance": auto_appearance,
    "scrollbars": scrollbars,
    "ui_sound_feedback": beep_feedback,
    "dock_show_recents": show_recents,
    "dock_mineffect": min_effect,
    "read_errors": errors,
}

try:
    with open("/tmp/home_office_productivity_result.json", "w") as f:
        json.dump(result, f, indent=2)
    print(json.dumps(result, indent=2))
except Exception as exc:
    fallback = {
        "task_start": task_start,
        "auto_appearance": False, "scrollbars": None,
        "ui_sound_feedback": None, "dock_show_recents": True,
        "dock_mineffect": None,
        "read_errors": errors + [f"writeout: {exc}"],
    }
    try:
        with open("/tmp/home_office_productivity_result.json", "w") as f:
            json.dump(fallback, f, indent=2)
    except Exception:
        pass
    print(json.dumps(fallback, indent=2))
PYEOF

echo "=== Export complete ==="
