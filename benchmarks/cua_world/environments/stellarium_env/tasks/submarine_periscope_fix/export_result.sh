#!/bin/bash
echo "=== Exporting submarine_periscope_fix result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

TASK_NAME="submarine_periscope_fix"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")
INITIAL_SS_COUNT=$(cat /tmp/${TASK_NAME}_initial_screenshot_count 2>/dev/null || echo "0")
SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
BRIEFING_DOC="/home/ga/Desktop/periscope_fix_plan.txt"

# Final screenshot
sleep 2
take_screenshot /tmp/${TASK_NAME}_end_screenshot.png

# Terminate Stellarium gracefully to flush config
echo "--- Terminating Stellarium to flush config ---"
pkill -SIGTERM stellarium 2>/dev/null || true

for i in $(seq 1 15); do
    if ! pgrep stellarium > /dev/null 2>&1; then
        break
    fi
    sleep 1
done
pkill -9 stellarium 2>/dev/null || true
sleep 2

# Parse config.ini
CONFIG_JSON=$(python3 << 'PYEOF'
import configparser, json, os

config_path = "/home/ga/.stellarium/config.ini"
result = {
    "config_exists": False,
    "lat_rad": None, "lon_rad": None, "alt_m": None,
    "flag_landscape": None,
    "flag_azimuthal_grid": None,
    "flag_constellation_drawing": None,
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

        lat = get_float('location_run_once', 'latitude')
        if lat is None or abs(lat - 0.705822) < 0.0001:
            lat2 = get_float('init_location', 'latitude')
            if lat2 is not None:
                lat = lat2
        result["lat_rad"] = lat

        lon = get_float('location_run_once', 'longitude')
        if lon is None or abs(lon - (-1.396192)) < 0.0001:
            lon2 = get_float('init_location', 'longitude')
            if lon2 is not None:
                lon = lon2
        result["lon_rad"] = lon
        
        result["alt_m"] = get_float('location_run_once', 'altitude', 0.0)

        result["flag_landscape"] = get_bool('landscape', 'flag_landscape', 'true')
        result["flag_azimuthal_grid"] = get_bool('viewing', 'flag_azimuthal_grid', 'false')
        result["flag_constellation_drawing"] = get_bool('viewing', 'flag_constellation_drawing', 'false')
        
    except Exception as e:
        result["config_error"] = str(e)

print(json.dumps(result))
PYEOF
)

# Count screenshots
CURRENT_SS_COUNT=$(ls -1 "$SCREENSHOT_DIR" 2>/dev/null | wc -l)
NEW_SS_COUNT=$((CURRENT_SS_COUNT - INITIAL_SS_COUNT))
SS_NEW_BY_TIME=0
if [ -d "$SCREENSHOT_DIR" ]; then
    SS_NEW_BY_TIME=$(find "$SCREENSHOT_DIR" -newer /tmp/${TASK_NAME}_start_ts -type f 2>/dev/null | wc -l)
fi
if [ "$SS_NEW_BY_TIME" -gt "$NEW_SS_COUNT" ]; then
    FINAL_SS_COUNT="$SS_NEW_BY_TIME"
else
    FINAL_SS_COUNT="$NEW_SS_COUNT"
fi

DOC_EXISTS="false"
DOC_CONTENT=""

if [ -f "$BRIEFING_DOC" ]; then
    DOC_EXISTS="true"
    DOC_CONTENT=$(cat "$BRIEFING_DOC" | tr -d '\000-\031' | sed 's/"/\\"/g' 2>/dev/null)
fi

python3 << PYEOF
import json

config = json.loads('''$CONFIG_JSON''')

result = {
    "task_name": "$TASK_NAME",
    "task_start": $TASK_START,
    "config_exists": config.get("config_exists", False),
    "lat_rad": config.get("lat_rad"),
    "lon_rad": config.get("lon_rad"),
    "flag_landscape": config.get("flag_landscape"),
    "flag_azimuthal_grid": config.get("flag_azimuthal_grid"),
    "flag_constellation_drawing": config.get("flag_constellation_drawing"),
    "new_screenshot_count": $FINAL_SS_COUNT,
    "doc_exists": "$DOC_EXISTS" == "true",
    "doc_content": "$DOC_CONTENT"
}

with open("/tmp/${TASK_NAME}_result.json", "w") as f:
    json.dump(result, f)
PYEOF

chmod 666 /tmp/${TASK_NAME}_result.json 2>/dev/null || true
echo "Export Complete"