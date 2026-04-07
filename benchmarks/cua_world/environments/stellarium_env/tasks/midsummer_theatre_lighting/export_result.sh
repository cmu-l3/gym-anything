#!/bin/bash
echo "=== Exporting midsummer_theatre_lighting result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

TASK_NAME="midsummer_theatre_lighting"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")
INITIAL_SS_COUNT=$(cat /tmp/${TASK_NAME}_initial_screenshot_count 2>/dev/null || echo "0")
SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
NOTES_FILE="/home/ga/Desktop/midsummer_lighting_notes.txt"
CONFIG_PATH="/home/ga/.stellarium/config.ini"

# 1. Take final screenshot before killing Stellarium
sleep 2
take_screenshot /tmp/${TASK_NAME}_end_screenshot.png

# 2. Gracefully terminate Stellarium to flush config.ini
echo "--- Terminating Stellarium to flush config ---"
pkill -SIGTERM stellarium 2>/dev/null || true

for i in $(seq 1 15); do
    if ! pgrep stellarium > /dev/null 2>&1; then break; fi
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
    "flag_constellation_drawing": None, "flag_constellation_art": None,
    "flag_constellation_name": None, "preset_sky_time": None
}

if os.path.exists(config_path):
    result["config_exists"] = True
    try:
        cfg = configparser.RawConfigParser()
        cfg.read(config_path)

        def get_bool(section, key, default='false'):
            try: return cfg.get(section, key).lower().strip() == 'true'
            except: return default.lower() == 'true'

        def get_float(section, key, default=None):
            try: return float(cfg.get(section, key))
            except: return default

        result["lat_rad"] = get_float('location_run_once', 'latitude')
        result["lon_rad"] = get_float('location_run_once', 'longitude')
        result["alt_m"] = get_float('location_run_once', 'altitude')
        result["flag_atmosphere"] = get_bool('landscape', 'flag_atmosphere', 'true')
        result["flag_landscape"] = get_bool('landscape', 'flag_landscape', 'true')
        result["flag_constellation_drawing"] = get_bool('viewing', 'flag_constellation_drawing', 'false')
        result["flag_constellation_art"] = get_bool('viewing', 'flag_constellation_art', 'false')
        
        # Stellarium sometimes stores this flag in different sections
        flag_name = get_bool('viewing', 'flag_constellation_name', 'false')
        if not flag_name:
            flag_name = get_bool('viewing', 'flag_constellation_names', 'false')
        if not flag_name:
            flag_name = get_bool('stars', 'flag_constellation_name', 'false')
        result["flag_constellation_name"] = flag_name
        
        result["preset_sky_time"] = get_float('navigation', 'preset_sky_time')
    except Exception as e:
        pass

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

# 5. Check Notes file
NOTES_EXISTS="false"
HAS_VEGA="false"
HAS_SATURN="false"
HAS_MOON="false"
HAS_TWILIGHT="false"

if [ -f "$NOTES_FILE" ]; then
    NOTES_EXISTS="true"
    if grep -qi "Vega" "$NOTES_FILE" 2>/dev/null; then HAS_VEGA="true"; fi
    if grep -qi "Saturn" "$NOTES_FILE" 2>/dev/null; then HAS_SATURN="true"; fi
    if grep -qi "Moon" "$NOTES_FILE" 2>/dev/null; then HAS_MOON="true"; fi
    if grep -qi "twilight\|sky\|bright\|dark\|dusk" "$NOTES_FILE" 2>/dev/null; then HAS_TWILIGHT="true"; fi
fi

# 6. Write result JSON
python3 << PYEOF
import json

config = json.loads('''$CONFIG_JSON''')
result = {
    "task_start": $TASK_START,
    "config_exists": config.get("config_exists", False),
    "lat_rad": config.get("lat_rad"),
    "lon_rad": config.get("lon_rad"),
    "flag_atmosphere": config.get("flag_atmosphere"),
    "flag_landscape": config.get("flag_landscape"),
    "flag_constellation_drawing": config.get("flag_constellation_drawing"),
    "flag_constellation_art": config.get("flag_constellation_art"),
    "flag_constellation_name": config.get("flag_constellation_name"),
    "preset_sky_time": config.get("preset_sky_time"),
    "new_screenshot_count": $FINAL_SS_COUNT,
    "notes_exists": $NOTES_EXISTS,
    "has_vega": $HAS_VEGA,
    "has_saturn": $HAS_SATURN,
    "has_moon": $HAS_MOON,
    "has_twilight": $HAS_TWILIGHT
}

with open("/tmp/${TASK_NAME}_result.json", "w") as f:
    json.dump(result, f)
PYEOF

echo "Result saved to /tmp/${TASK_NAME}_result.json"
cat /tmp/${TASK_NAME}_result.json