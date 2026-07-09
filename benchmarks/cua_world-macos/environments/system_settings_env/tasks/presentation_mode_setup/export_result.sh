#!/bin/bash
# post_task hook for presentation_mode_setup on system_settings_env.
#
# Reads the five `defaults` domains the agent should have modified and
# writes /tmp/presentation_mode_setup_result.json for the verifier.
#
# Anti-Pattern #12 ("Python Heredoc stdout Capture in export_result.sh
# Silently Fails on Exception"): every embedded Python heredoc wraps its
# main logic in try/except and writes a safe default if anything fails,
# so the verifier always reads valid JSON. We also do NOT use `set -e`
# so individual `defaults read` failures (missing key) don't terminate
# the script.
set -u   # NOT -e — partial reads must keep going

echo "=== Exporting presentation_mode_setup results ==="

/usr/sbin/screencapture -x /tmp/task_end.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
echo "task_start_unix=$TASK_START"

# Force cfprefsd to flush before reading — defaults writes from the agent
# (whether via UI or Terminal) may not have hit disk yet, and `defaults
# read` reads via the cfprefsd daemon. A killall + brief sleep guarantees
# a fresh read.
killall cfprefsd 2>/dev/null || true
sleep 1

# ---------------------------------------------------------------------------
# Read each pref. `defaults read` exits with rc=1 and prints to stderr if
# the key is absent. We capture stdout only; absence → empty string,
# which Python below turns into JSON `null`.
# ---------------------------------------------------------------------------
APPEARANCE=$(defaults read -g AppleInterfaceStyle 2>/dev/null || echo "")
DOCK_ORIENT=$(defaults read com.apple.dock orientation 2>/dev/null || echo "")
DOCK_AUTOHIDE=$(defaults read com.apple.dock autohide 2>/dev/null || echo "")
DOCK_TILESIZE=$(defaults read com.apple.dock tilesize 2>/dev/null || echo "")
CLOCK_DATEFORMAT=$(defaults read com.apple.menuextra.clock DateFormat 2>/dev/null || echo "")
CLOCK_SHOWAMPM=$(defaults read com.apple.menuextra.clock ShowAMPM 2>/dev/null || echo "")

echo "raw reads:"
echo "  AppleInterfaceStyle=${APPEARANCE}"
echo "  dock.orientation=${DOCK_ORIENT}"
echo "  dock.autohide=${DOCK_AUTOHIDE}"
echo "  dock.tilesize=${DOCK_TILESIZE}"
echo "  clock.DateFormat=${CLOCK_DATEFORMAT}"
echo "  clock.ShowAMPM=${CLOCK_SHOWAMPM}"

# ---------------------------------------------------------------------------
# Stitch the result JSON. One python call so quoting is right and we can
# normalize the booleans/ints inline. Anti-Pattern #12: try/except + safe
# defaults; the outermost print never raises.
# ---------------------------------------------------------------------------
/usr/bin/python3 - "$TASK_START" "$APPEARANCE" "$DOCK_ORIENT" "$DOCK_AUTOHIDE" "$DOCK_TILESIZE" "$CLOCK_DATEFORMAT" "$CLOCK_SHOWAMPM" << 'PYEOF'
import json, sys

def to_int_or_none(s):
    try:
        return int(str(s).strip())
    except Exception:
        return None

def to_bool_from_defaults(s):
    """`defaults read foo bar` prints `1` for true and `0` for false for
    Boolean keys. Anything else (empty, missing) → False.
    """
    return str(s).strip() == "1"

def first_or_none(s):
    s = str(s).strip()
    return s if s else None

errors = []
try:
    task_start = int(sys.argv[1] or 0)
except Exception as exc:
    task_start = 0
    errors.append(f"task_start parse: {type(exc).__name__}: {exc}")

appearance       = first_or_none(sys.argv[2])    # "Dark" or None (Light = absent)
dock_orientation = first_or_none(sys.argv[3])    # "bottom" / "left" / "right" / None
dock_autohide    = to_bool_from_defaults(sys.argv[4])
dock_tilesize    = to_int_or_none(sys.argv[5])
clock_dateformat = first_or_none(sys.argv[6])
clock_showampm_raw = first_or_none(sys.argv[7])

# Two complementary signals exist for "24-hour clock". Live test on the
# use.computer fleet (2026-05) showed:
#   - Toggling "Show AM/PM" off in System Settings > Control Center > Clock Options
#     writes ShowAMPM=0 to com.apple.menuextra.clock but does NOT immediately
#     rewrite DateFormat (still "EEE MMM d  h:mm a"). The MENU BAR however
#     renders 24-hour because SystemUIServer reads ShowAMPM.
#   - `defaults write com.apple.menuextra.clock DateFormat "EEE MMM d  HH:mm"`
#     directly sets a 24-hour pattern; the menu bar honours it.
# So the verifier accepts EITHER signal as proof of "24-hour clock active":
#   (a) DateFormat string contains "HH" (uppercase 24h marker, UTS#35), OR
#   (b) ShowAMPM == 0 (false) — the System Settings UI path.
if clock_showampm_raw is None:
    clock_showampm = None
else:
    try:
        clock_showampm = bool(int(clock_showampm_raw))
    except Exception:
        clock_showampm = None

clock_is_24h = False
if clock_dateformat is not None:
    fmt = clock_dateformat
    has_24h_marker = "HH" in fmt
    has_ampm_marker = (" a" in fmt) or fmt.endswith("a") or "aa" in fmt
    if has_24h_marker and not has_ampm_marker:
        clock_is_24h = True
# UI-path signal: ShowAMPM toggled off in Clock Options
if clock_showampm is False:
    clock_is_24h = True

# Derived: any setting actually changed from the documented baseline.
# Baseline is: AppleInterfaceStyle absent, dock.orientation="bottom",
# dock.autohide=False, dock.tilesize=48, DateFormat="EEE MMM d  h:mm a",
# ShowAMPM unset (default macOS behaviour treats absence as true / 12h).
any_touched = (
    appearance is not None
    or (dock_orientation is not None and dock_orientation != "bottom")
    or dock_autohide is True
    or (dock_tilesize is not None and dock_tilesize != 48)
    or (clock_dateformat is not None and clock_dateformat != "EEE MMM d  h:mm a")
    or clock_showampm is False
)

result = {
    "task_start": task_start,
    "appearance": appearance,
    "dock_orientation": dock_orientation,
    "dock_autohide": dock_autohide,
    "dock_tilesize": dock_tilesize,
    "clock_date_format": clock_dateformat,
    "clock_show_ampm": clock_showampm,
    "clock_is_24h": clock_is_24h,
    "any_settings_touched": any_touched,
    "read_errors": errors,
}

try:
    with open("/tmp/presentation_mode_setup_result.json", "w") as f:
        json.dump(result, f, indent=2)
    print(json.dumps(result, indent=2))
except Exception as exc:
    # Last-resort: at least write a parseable minimal JSON so the verifier
    # can return a clear error rather than "could not retrieve result file".
    fallback = {
        "task_start": task_start, "appearance": None, "dock_orientation": None,
        "dock_autohide": False, "dock_tilesize": None,
        "clock_date_format": None, "clock_show_ampm": None, "clock_is_24h": False,
        "any_settings_touched": False,
        "read_errors": errors + [f"writeout: {type(exc).__name__}: {exc}"],
    }
    try:
        with open("/tmp/presentation_mode_setup_result.json", "w") as f:
            json.dump(fallback, f, indent=2)
    except Exception:
        pass
    print(json.dumps(fallback, indent=2))
PYEOF

echo "=== Export complete ==="
