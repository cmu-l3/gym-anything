#!/bin/bash
echo "=== Exporting astrotourism_tour_planner result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

TASK_NAME="astrotourism_tour_planner"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")
INITIAL_SS_COUNT=$(cat /tmp/${TASK_NAME}_initial_screenshot_count 2>/dev/null || echo "0")
SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
BRIEFING_FILE="/home/ga/Desktop/tour_briefing.txt"
CONFIG_PATH="/home/ga/.stellarium/config.ini"

# 1. Take final screenshot (while Stellarium is still running)
sleep 2
take_screenshot /tmp/${TASK_NAME}_end_screenshot.png

# 2. Gracefully terminate Stellarium to force config.ini save
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

# Force kill if still running
pkill -9 stellarium 2>/dev/null || true
sleep 2

# 3. Parse config.ini with Python
CONFIG_JSON=$(python3 << 'PYEOF'
import configparser, json, os

config_path = "/home/ga/.stellarium/config.ini"
result = {
    "config_exists": False,
    "lat_rad": None,
    "lon_rad": None,
    "flag_atmosphere": None,
    "flag_landscape": None,
    "flag_constellation_drawing": None,
    "flag_constellation_name": None,
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

        # Display flags
        result["flag_atmosphere"] = get_bool('landscape', 'flag_atmosphere', 'true')
        result["flag_landscape"] = get_bool('landscape', 'flag_landscape', 'true')
        result["flag_constellation_drawing"] = get_bool('viewing', 'flag_constellation_drawing', 'false')
        result["flag_constellation_name"] = get_bool('viewing', 'flag_constellation_name', 'false')

    except Exception as e:
        result["config_error"] = str(e)

print(json.dumps(result))
PYEOF
)

echo "Config parsed: $CONFIG_JSON"

# 4. Count new screenshots
CURRENT_SS_COUNT=$(ls "$SCREENSHOT_DIR" 2>/dev/null | wc -l)
NEW_SS_COUNT=$((CURRENT_SS_COUNT - INITIAL_SS_COUNT))
echo "Screenshots: initial=$INITIAL_SS_COUNT, current=$CURRENT_SS_COUNT, new=$NEW_SS_COUNT"

# Also count screenshots explicitly newer than task start (prevents gaming by renaming files)
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

# 5. Check briefing file
BRIEFING_EXISTS="false"
BRIEFING_CREATED_DURING_TASK="false"
HAS_CRUX="false"
HAS_MAGELLANIC="false"
HAS_CENTAURI="false"
BRIEFING_SIZE=0

if [ -f "$BRIEFING_FILE" ]; then
    BRIEFING_EXISTS="true"
    BRIEFING_SIZE=$(wc -c < "$BRIEFING_FILE" 2>/dev/null || echo "0")
    
    FILE_MTIME=$(stat -c %Y "$BRIEFING_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        BRIEFING_CREATED_DURING_TASK="true"
    fi

    if grep -qi "Crux\|Southern Cross" "$BRIEFING_FILE" 2>/dev/null; then
        HAS_CRUX="true"
    fi
    if grep -qi "Magellanic\|LMC" "$BRIEFING_FILE" 2>/dev/null; then
        HAS_MAGELLANIC="true"
    fi
    if grep -qi "Alpha Centauri\|Centauri" "$BRIEFING_FILE" 2>/dev/null; then
        HAS_CENTAURI="true"
    fi
fi

# 6. Write final result JSON
python3 << PYEOF
import json

config = json.loads('''$CONFIG_JSON''')

result = {
    "task_name": "$TASK_NAME",
    "task_start": $TASK_START,
    "config_exists": config.get("config_exists", False),
    "lat_rad": config.get("lat_rad"),
    "lon_rad": config.get("lon_rad"),
    "flag_atmosphere": config.get("flag_atmosphere"),
    "flag_landscape": config.get("flag_landscape"),
    "flag_constellation_drawing": config.get("flag_constellation_drawing"),
    "flag_constellation_name": config.get("flag_constellation_name"),
    "new_screenshot_count": $FINAL_SS_COUNT,
    "briefing_exists": $BRIEFING_EXISTS,
    "briefing_created_during_task": $BRIEFING_CREATED_DURING_TASK,
    "briefing_has_crux": $HAS_CRUX,
    "briefing_has_magellanic": $HAS_MAGELLANIC,
    "briefing_has_centauri": $HAS_CENTAURI,
    "briefing_size": $BRIEFING_SIZE
}

with open('/tmp/${TASK_NAME}_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/${TASK_NAME}_result.json 2>/dev/null || true

echo "=== Export Complete ==="
cat /tmp/${TASK_NAME}_result.json