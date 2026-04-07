#!/bin/bash
echo "=== Exporting cultural_sky_heritage result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

TASK_NAME="cultural_sky_heritage"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")
INITIAL_SS_COUNT=$(cat /tmp/${TASK_NAME}_initial_screenshot_count 2>/dev/null || echo "0")
SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
NOTES_FILE="/home/ga/Desktop/exhibit_sky_notes.txt"

# 1. Take final screenshot before killing Stellarium
sleep 2
take_screenshot /tmp/${TASK_NAME}_end_screenshot.png

# 2. Gracefully terminate Stellarium to flush config.ini
echo "--- Terminating Stellarium to flush config ---"
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

# 3. Parse config.ini for verification
CONFIG_JSON=$(python3 << 'PYEOF'
import configparser, json, os

config_path = "/home/ga/.stellarium/config.ini"
result = {
    "config_exists": False,
    "lat_rad": None, "lon_rad": None,
    "flag_atmosphere": None, "flag_landscape": None,
    "flag_constellation_drawing": None, "flag_constellation_name": None,
    "sky_culture": None,
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
        result["flag_atmosphere"] = get_bool('landscape', 'flag_atmosphere', 'true')
        result["flag_landscape"] = get_bool('landscape', 'flag_landscape', 'true')
        result["flag_constellation_drawing"] = get_bool('viewing', 'flag_constellation_drawing', 'false')
        result["flag_constellation_name"] = get_bool('viewing', 'flag_constellation_name', 'false')
        
        try:
            result["sky_culture"] = cfg.get('localization', 'sky_culture').lower().strip()
        except:
            result["sky_culture"] = "western"

    except Exception as e:
        result["config_error"] = str(e)

print(json.dumps(result))
PYEOF
)

# 4. Count new screenshots (using timestamps to prevent gaming)
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
echo "New screenshots: $FINAL_SS_COUNT"

# 5. Check notes file requirements
NOTES_EXISTS="false"
HAS_GIZA="false"
HAS_WESTERN="false"
HAS_EGYPTIAN="false"
HAS_CHINESE="false"
HAS_BETELGEUSE="false"

if [ -f "$NOTES_FILE" ]; then
    NOTES_EXISTS="true"
    grep -qiE "giza|pyramid" "$NOTES_FILE" && HAS_GIZA="true"
    grep -qi "western" "$NOTES_FILE" && HAS_WESTERN="true"
    grep -qi "egyptian" "$NOTES_FILE" && HAS_EGYPTIAN="true"
    grep -qi "chinese" "$NOTES_FILE" && HAS_CHINESE="true"
    grep -qi "betelgeuse" "$NOTES_FILE" && HAS_BETELGEUSE="true"
fi

# 6. Write exported result JSON
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
    "sky_culture": config.get("sky_culture"),
    "new_screenshot_count": $FINAL_SS_COUNT,
    "notes_exists": $NOTES_EXISTS,
    "has_giza": $HAS_GIZA,
    "has_western": $HAS_WESTERN,
    "has_egyptian": $HAS_EGYPTIAN,
    "has_chinese": $HAS_CHINESE,
    "has_betelgeuse": $HAS_BETELGEUSE
}

with open("/tmp/${TASK_NAME}_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/${TASK_NAME}_result.json 2>/dev/null || true
echo "Result exported to /tmp/${TASK_NAME}_result.json"