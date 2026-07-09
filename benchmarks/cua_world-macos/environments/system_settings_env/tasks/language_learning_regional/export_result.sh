#!/bin/bash
# post_task hook for language_learning_regional on system_settings_env.
#
# Reads language, region, and time format settings and writes
# /tmp/language_learning_regional_result.json for the verifier.
# Anti-Pattern #12: python heredoc uses try/except, always writes valid JSON.
set -u   # NOT -e

echo "=== Exporting language_learning_regional results ==="

/usr/sbin/screencapture -x /tmp/task_end.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
echo "task_start_unix=$TASK_START"

killall cfprefsd 2>/dev/null || true
sleep 1

# ---------------------------------------------------------------------------
# Read settings. Arrays and dicts require Python to parse properly.
# ---------------------------------------------------------------------------
LANGUAGES=$(defaults read -g AppleLanguages 2>/dev/null || echo "")
MEASUREMENT=$(defaults read -g AppleMeasurementUnits 2>/dev/null || echo "")
TEMPERATURE=$(defaults read -g AppleTemperatureUnit 2>/dev/null || echo "")
CLOCK_DATEFORMAT=$(defaults read com.apple.menuextra.clock DateFormat 2>/dev/null || echo "")
CLOCK_SHOWAMPM=$(defaults read com.apple.menuextra.clock ShowAMPM 2>/dev/null || echo "")
# ICUForce24HourTime — may or may not exist depending on how agent set 24h
ICU_24H=$(defaults read -g AppleICUForce24HourTime 2>/dev/null || echo "")

echo "raw reads:"
echo "  AppleLanguages=${LANGUAGES}"
echo "  AppleMeasurementUnits=${MEASUREMENT}"
echo "  AppleTemperatureUnit=${TEMPERATURE}"
echo "  clock.DateFormat=${CLOCK_DATEFORMAT}"
echo "  clock.ShowAMPM=${CLOCK_SHOWAMPM}"
echo "  AppleICUForce24HourTime=${ICU_24H}"

/usr/bin/python3 - "$TASK_START" \
    "$MEASUREMENT" "$TEMPERATURE" \
    "$CLOCK_DATEFORMAT" "$CLOCK_SHOWAMPM" "$ICU_24H" << 'PYEOF'
import json, sys, subprocess, plistlib, os

errors = []

try:
    task_start = int(sys.argv[1] or 0)
except Exception as e:
    task_start = 0
    errors.append(f"task_start: {e}")

measurement  = str(sys.argv[2]).strip() or None
temperature  = str(sys.argv[3]).strip() or None
clock_fmt    = str(sys.argv[4]).strip() or None
showampm_raw = str(sys.argv[5]).strip() or None
icu24h_raw   = str(sys.argv[6]).strip() or None

# ---- C1: Languages — read via defaults subprocess to get the array ----
has_french = False
try:
    r = subprocess.run(
        ["defaults", "read", "-g", "AppleLanguages"],
        capture_output=True, text=True, timeout=10
    )
    langs_str = r.stdout.strip()
    # The output looks like: (\n    "en-US",\n    "fr-FR"\n)
    # Check for any "fr" prefix (fr, fr-FR, fr-CH, etc.)
    has_french = any(
        token.strip().strip('"').strip("'").lower().startswith("fr")
        for token in langs_str.replace("(", "").replace(")", "").split(",")
    )
except Exception as e:
    errors.append(f"AppleLanguages read: {e}")

# ---- C4: 24-hour time — two signals ----
clock_is_24h = False
if clock_fmt:
    has_HH = "HH" in clock_fmt
    has_ampm_marker = " a" in clock_fmt or clock_fmt.endswith("a")
    if has_HH and not has_ampm_marker:
        clock_is_24h = True
if showampm_raw == "0":
    clock_is_24h = True
if icu24h_raw == "1":
    clock_is_24h = True

# ---- C5: First day of week (Monday = 2) ----
first_weekday = None
try:
    # Read from GlobalPreferences plist directly for reliability
    plist_path = os.path.expanduser("~/Library/Preferences/.GlobalPreferences.plist")
    if os.path.exists(plist_path):
        with open(plist_path, "rb") as f:
            prefs = plistlib.load(f)
        fw = prefs.get("AppleFirstWeekday", {})
        if isinstance(fw, dict):
            # macOS stores gregorian as a string on some versions; coerce to int
            g = fw.get("gregorian")
            if g is not None:
                try:
                    first_weekday = int(g)
                except (ValueError, TypeError):
                    first_weekday = None
        elif fw is not None:
            try:
                first_weekday = int(fw)
            except (ValueError, TypeError):
                first_weekday = None
    else:
        # Fallback: parse defaults read output
        r2 = subprocess.run(
            ["defaults", "read", "-g", "AppleFirstWeekday"],
            capture_output=True, text=True, timeout=10
        )
        out = r2.stdout.strip()
        # Looks like: {\n    gregorian = 2;\n}
        import re
        m = re.search(r'gregorian\s*=\s*(\d+)', out)
        if m:
            first_weekday = int(m.group(1))
except Exception as e:
    errors.append(f"AppleFirstWeekday read: {e}")

result = {
    "task_start": task_start,
    "has_french_language": has_french,
    "measurement_units": measurement,
    "temperature_unit": temperature,
    "clock_is_24h": clock_is_24h,
    "clock_date_format": clock_fmt,
    "first_weekday_gregorian": first_weekday,
    "read_errors": errors,
}

try:
    with open("/tmp/language_learning_regional_result.json", "w") as f:
        json.dump(result, f, indent=2)
    print(json.dumps(result, indent=2))
except Exception as exc:
    fallback = {
        "task_start": task_start,
        "has_french_language": False, "measurement_units": None,
        "temperature_unit": None, "clock_is_24h": False,
        "clock_date_format": None, "first_weekday_gregorian": None,
        "read_errors": errors + [f"writeout: {exc}"],
    }
    try:
        with open("/tmp/language_learning_regional_result.json", "w") as f:
            json.dump(fallback, f, indent=2)
    except Exception:
        pass
    print(json.dumps(fallback, indent=2))
PYEOF

echo "=== Export complete ==="
