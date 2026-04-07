#!/bin/bash
echo "=== Exporting galactic_center_survey_planning result ==="

TASK_NAME="galactic_center_survey_planning"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")
INITIAL_SS_COUNT=$(cat /tmp/${TASK_NAME}_initial_screenshot_count 2>/dev/null || echo "0")
SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
PLAN_NOTES="/home/ga/Desktop/galactic_survey_plan.txt"
CONFIG_PATH="/home/ga/.stellarium/config.ini"

# 1. Take final screenshot before killing Stellarium
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_end_screenshot.png 2>/dev/null || \
DISPLAY=:1 scrot /tmp/${TASK_NAME}_end_screenshot.png 2>/dev/null || true

# 2. Gracefully terminate Stellarium to flush config.ini
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

# 3. Parse config.ini
CONFIG_JSON=$(python3 << 'PYEOF'
import configparser, json, os

config_path = "/home/ga/.stellarium/config.ini"
result = {
    "config_exists": False,
    "lat_rad": None, "lon_rad": None, "alt_m": None,
    "flag_atmosphere": None, "flag_landscape": None,
    "flag_galactic_grid": None, "flag_galactic_equator": None,
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

        result["lat_rad"] = get_float('location_run_once', 'latitude', 0.0)
        result["lon_rad"] = get_float('location_run_once', 'longitude', 0.0)
        result["alt_m"] = get_float('location_run_once', 'altitude', 0.0)
        
        result["flag_atmosphere"] = get_bool('landscape', 'flag_atmosphere', 'true')
        result["flag_landscape"] = get_bool('landscape', 'flag_landscape', 'true')
        result["flag_galactic_grid"] = get_bool('viewing', 'flag_galactic_grid', 'false')
        result["flag_galactic_equator"] = get_bool('viewing', 'flag_galactic_equator', 'false')

    except Exception as e:
        result["config_error"] = str(e)

print(json.dumps(result))
PYEOF
)

# 4. Check screenshots
CURRENT_SS_COUNT=$(ls "$SCREENSHOT_DIR" 2>/dev/null | wc -l)
NEW_SS_COUNT=$((CURRENT_SS_COUNT - INITIAL_SS_COUNT))
SS_NEW_BY_TIME=0
if [ -d "$SCREENSHOT_DIR" ]; then
    SS_NEW_BY_TIME=$(find "$SCREENSHOT_DIR" -newer /tmp/${TASK_NAME}_start_ts -type f 2>/dev/null | wc -l)
fi
FINAL_SS_COUNT=$(( SS_NEW_BY_TIME > NEW_SS_COUNT ? SS_NEW_BY_TIME : NEW_SS_COUNT ))

# 5. Check survey notes file
NOTES_EXISTS="false"
NOTES_HAS_SAG="false"
NOTES_HAS_ALMA="false"
NOTES_HAS_DATE="false"

if [ -f "$PLAN_NOTES" ]; then
    NOTES_EXISTS="true"
    if grep -qi "Sagittarius" "$PLAN_NOTES" 2>/dev/null; then NOTES_HAS_SAG="true"; fi
    if grep -qi "ALMA" "$PLAN_NOTES" 2>/dev/null; then NOTES_HAS_ALMA="true"; fi
    if grep -qi "July 15" "$PLAN_NOTES" 2>/dev/null; then NOTES_HAS_DATE="true"; fi
fi

# 6. Write result JSON
python3 << PYEOF
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
    "flag_galactic_grid": config.get("flag_galactic_grid"),
    "flag_galactic_equator": config.get("flag_galactic_equator"),
    "new_screenshot_count": $FINAL_SS_COUNT,
    "notes_exists": str("$NOTES_EXISTS").lower() == "true",
    "notes_has_sagittarius": str("$NOTES_HAS_SAG").lower() == "true",
    "notes_has_alma": str("$NOTES_HAS_ALMA").lower() == "true",
    "notes_has_date": str("$NOTES_HAS_DATE").lower() == "true"
}

with open("/tmp/${TASK_NAME}_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/${TASK_NAME}_result.json
echo "Exported results to /tmp/${TASK_NAME}_result.json"
cat /tmp/${TASK_NAME}_result.json
echo "=== Export Complete ==="