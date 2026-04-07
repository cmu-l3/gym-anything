#!/bin/bash
echo "=== Exporting hilal_crescent_assessment result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

TASK_NAME="hilal_crescent_assessment"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")
INITIAL_SS_COUNT=$(cat /tmp/${TASK_NAME}_initial_screenshot_count 2>/dev/null || echo "0")
SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
REPORT_NOTES="/home/ga/Desktop/hilal_report.txt"
CONFIG_PATH="/home/ga/.stellarium/config.ini"

# ── 1. Take final screenshot while Stellarium is still running ──
sleep 2
take_screenshot /tmp/${TASK_NAME}_end_screenshot.png

# ── 2. Gracefully terminate Stellarium to flush config.ini ──
echo "--- Terminating Stellarium to flush config ---"
pkill -SIGTERM stellarium 2>/dev/null || true

# Wait for Stellarium to exit cleanly (config is saved on exit)
for i in $(seq 1 15); do
    if ! pgrep stellarium > /dev/null 2>&1; then
        echo "Stellarium exited after ${i}s"
        break
    fi
    sleep 1
done

# Force kill if still hanging
pkill -9 stellarium 2>/dev/null || true
sleep 2

# ── 3. Parse config.ini with Python ──
CONFIG_JSON=$(python3 << 'PYEOF'
import configparser, json, os

config_path = "/home/ga/.stellarium/config.ini"
result = {
    "config_exists": False,
    "lat_rad": None,
    "lon_rad": None,
    "alt_m": None,
    "flag_atmosphere": None,
    "flag_landscape": None,
    "flag_azimuthal_grid": None,
    "preset_sky_time": None,
    "config_error": None
}

if os.path.exists(config_path):
    result["config_exists"] = True
    try:
        cfg = configparser.RawConfigParser()
        cfg.read(config_path)

        def get_bool(section, key, default='false'):
            try:
                return cfg.get(section, key).lower().strip() == 'true'
            except:
                return default.lower() == 'true'

        def get_float(section, key, default=None):
            try:
                return float(cfg.get(section, key))
            except:
                return default

        # Location (radians)
        result["lat_rad"] = get_float('location_run_once', 'latitude', 0.0)
        result["lon_rad"] = get_float('location_run_once', 'longitude', 0.0)
        result["alt_m"] = get_float('location_run_once', 'altitude', 0.0)

        # Display flags
        result["flag_atmosphere"] = get_bool('landscape', 'flag_atmosphere', 'true')
        result["flag_landscape"] = get_bool('landscape', 'flag_landscape', 'true')
        result["flag_azimuthal_grid"] = get_bool('viewing', 'flag_azimuthal_grid', 'false')

        # Navigation time (Julian Day)
        result["preset_sky_time"] = get_float('navigation', 'preset_sky_time', 2451545.0)

    except Exception as e:
        result["config_error"] = str(e)

print(json.dumps(result))
PYEOF
)

echo "Config parsed: $CONFIG_JSON"

# ── 4. Count new screenshots ──
CURRENT_SS_COUNT=$(ls -1 "$SCREENSHOT_DIR" 2>/dev/null | wc -l)
NEW_SS_COUNT=$((CURRENT_SS_COUNT - INITIAL_SS_COUNT))
echo "Screenshots: initial=$INITIAL_SS_COUNT, current=$CURRENT_SS_COUNT, new=$NEW_SS_COUNT"

SS_NEW_BY_TIME=0
if [ -d "$SCREENSHOT_DIR" ]; then
    SS_NEW_BY_TIME=$(find "$SCREENSHOT_DIR" -newer /tmp/${TASK_NAME}_start_ts -type f 2>/dev/null | wc -l)
fi
echo "Screenshots newer than task start: $SS_NEW_BY_TIME"

if [ "$SS_NEW_BY_TIME" -gt "$NEW_SS_COUNT" ]; then
    FINAL_SS_COUNT="$SS_NEW_BY_TIME"
else
    FINAL_SS_COUNT="$NEW_SS_COUNT"
fi

# ── 5. Check Hilal Report file ──
REPORT_EXISTS="false"
REPORT_HAS_TARGET_KEYWORD="false"
REPORT_HAS_CONTEXT_KEYWORD="false"

if [ -f "$REPORT_NOTES" ]; then
    REPORT_EXISTS="true"
    
    # Check for target keywords (moon, hilal, crescent)
    if grep -qi "moon\|hilal\|crescent" "$REPORT_NOTES" 2>/dev/null; then
        REPORT_HAS_TARGET_KEYWORD="true"
    fi

    # Check for context keywords (mecca, ramadan, 1444)
    if grep -qi "mecca\|ramadan\|1444" "$REPORT_NOTES" 2>/dev/null; then
        REPORT_HAS_CONTEXT_KEYWORD="true"
    fi
fi

# ── 6. Write final result JSON ──
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 << PYEOF > "$TEMP_JSON"
import json

config = json.loads('''$CONFIG_JSON''')

result = {
    "task_name": "$TASK_NAME",
    "task_start": $TASK_START,
    "config_exists": config.get("config_exists", False),
    "lat_rad": config.get("lat_rad"),
    "lon_rad": config.get("lon_rad"),
    "alt_m": config.get("alt_m"),
    "flag_atmosphere": config.get("flag_atmosphere"),
    "flag_landscape": config.get("flag_landscape"),
    "flag_azimuthal_grid": config.get("flag_azimuthal_grid"),
    "preset_sky_time": config.get("preset_sky_time"),
    "new_screenshot_count": $FINAL_SS_COUNT,
    "report_exists": "$REPORT_EXISTS" == "true",
    "report_has_target": "$REPORT_HAS_TARGET_KEYWORD" == "true",
    "report_has_context": "$REPORT_HAS_CONTEXT_KEYWORD" == "true",
    "config_error": config.get("config_error")
}

print(json.dumps(result, indent=2))
PYEOF

RESULT_PATH="/tmp/${TASK_NAME}_result.json"
rm -f "$RESULT_PATH" 2>/dev/null || sudo rm -f "$RESULT_PATH" 2>/dev/null || true
cp "$TEMP_JSON" "$RESULT_PATH" 2>/dev/null || sudo cp "$TEMP_JSON" "$RESULT_PATH"
chmod 666 "$RESULT_PATH" 2>/dev/null || sudo chmod 666 "$RESULT_PATH" 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to $RESULT_PATH"
cat "$RESULT_PATH"
echo "=== Export complete ==="