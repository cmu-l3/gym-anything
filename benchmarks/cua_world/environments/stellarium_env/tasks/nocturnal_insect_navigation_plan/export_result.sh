#!/bin/bash
echo "=== Exporting nocturnal_insect_navigation_plan result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

TASK_NAME="nocturnal_insect_navigation_plan"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")
INITIAL_SS_COUNT=$(cat /tmp/${TASK_NAME}_initial_screenshot_count 2>/dev/null || echo "0")
SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
NOTES_FILE="/home/ga/Desktop/beetle_field_plan.txt"

# 1. Take final screenshot before killing Stellarium
sleep 2
take_screenshot /tmp/${TASK_NAME}_end_screenshot.png

# 2. Gracefully terminate Stellarium
# This forces Stellarium to flush any state, though the task strictly 
# requires the agent to explicitly use "Save settings".
echo "--- Terminating Stellarium to check saved config ---"
pkill -SIGTERM stellarium 2>/dev/null || true

for i in $(seq 1 15); do
    if ! pgrep stellarium > /dev/null 2>&1; then
        echo "Stellarium exited after ${i}s"
        break
    fi
    sleep 1
done

pkill -9 stellarium 2>/dev/null || true
sleep 2

# 3. Parse config.ini
# If the agent correctly hit "Save settings", the required config values will be in here.
CONFIG_JSON=$(python3 << 'PYEOF'
import configparser, json, os

config_path = "/home/ga/.stellarium/config.ini"
result = {
    "config_exists": False,
    "lat_rad": None, "lon_rad": None, "alt_m": None,
    "flag_atmosphere": None, 
    "flag_azimuthal_grid": None,
    "flag_galactic_grid": None,
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
        result["flag_azimuthal_grid"] = get_bool('viewing', 'flag_azimuthal_grid', 'false')
        result["flag_galactic_grid"] = get_bool('viewing', 'flag_galactic_grid', 'false')
    except Exception as e:
        result["config_error"] = str(e)

print(json.dumps(result))
PYEOF
)

# 4. Count new screenshots
CURRENT_SS_COUNT=$(ls "$SCREENSHOT_DIR" 2>/dev/null | wc -l)
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
echo "New screenshots: $FINAL_SS_COUNT"

# 5. Check beetle_field_plan.txt notes file
NOTES_EXISTS="false"
NOTES_HAS_CRUX="false"
NOTES_HAS_SA="false"
NOTES_HAS_NOV="false"
NOTES_HAS_GALACTIC="false"
NOTES_SIZE=0

if [ -f "$NOTES_FILE" ]; then
    NOTES_EXISTS="true"
    NOTES_SIZE=$(wc -c < "$NOTES_FILE" 2>/dev/null || echo "0")
    if grep -qi "Crux\|cross" "$NOTES_FILE" 2>/dev/null; then
        NOTES_HAS_CRUX="true"
    fi
    if grep -qi "South Africa\|Kalahari" "$NOTES_FILE" 2>/dev/null; then
        NOTES_HAS_SA="true"
    fi
    if grep -qi "Nov\|11/" "$NOTES_FILE" 2>/dev/null; then
        NOTES_HAS_NOV="true"
    fi
    if grep -qi "Galactic\|Milky Way" "$NOTES_FILE" 2>/dev/null; then
        NOTES_HAS_GALACTIC="true"
    fi
fi

echo "Field Plan notes: exists=$NOTES_EXISTS, crux=$NOTES_HAS_CRUX, sa=$NOTES_HAS_SA, nov=$NOTES_HAS_NOV, galactic=$NOTES_HAS_GALACTIC"

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
    "flag_azimuthal_grid": config.get("flag_azimuthal_grid"),
    "flag_galactic_grid": config.get("flag_galactic_grid"),
    "config_error": config.get("config_error"),
    "new_screenshot_count": $FINAL_SS_COUNT,
    "notes_exists": $NOTES_EXISTS,
    "notes_size_bytes": $NOTES_SIZE,
    "notes_has_crux": $NOTES_HAS_CRUX,
    "notes_has_sa": $NOTES_HAS_SA,
    "notes_has_nov": $NOTES_HAS_NOV,
    "notes_has_galactic": $NOTES_HAS_GALACTIC
}

with open('/tmp/${TASK_NAME}_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/${TASK_NAME}_result.json 2>/dev/null || true
echo "=== Result Exported ==="
cat /tmp/${TASK_NAME}_result.json