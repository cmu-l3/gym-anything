#!/bin/bash
echo "=== Exporting urban_light_pollution_advocacy result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

TASK_NAME="urban_light_pollution_advocacy"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")
INITIAL_SS_COUNT=$(cat /tmp/${TASK_NAME}_initial_screenshot_count 2>/dev/null || echo "0")
SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
PRESENTATION_NOTES="/home/ga/Desktop/dark_sky_presentation.txt"
CONFIG_PATH="/home/ga/.stellarium/config.ini"

# ── 1. Take final screenshot before killing Stellarium ────────────────────────
sleep 2
take_screenshot /tmp/${TASK_NAME}_end_screenshot.png

# ── 2. Gracefully terminate Stellarium to flush config.ini ───────────────────
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

# ── 3. Parse config.ini ───────────────────────────────────────────────────────
CONFIG_JSON=$(python3 << 'PYEOF'
import configparser, json, os

config_path = "/home/ga/.stellarium/config.ini"
result = {
    "config_exists": False,
    "lat_rad": None, "lon_rad": None,
    "flag_atmosphere": None,
    "flag_constellation_drawing": None,
    "flag_light_pollution_database": None,
    "light_pollution_luminance": None,
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
        result["flag_light_pollution_database"] = get_bool('landscape', 'flag_light_pollution_database', 'true')
        result["light_pollution_luminance"] = get_float('landscape', 'light_pollution_luminance', -1.0)
        result["flag_constellation_drawing"] = get_bool('viewing', 'flag_constellation_drawing', 'false')
        
    except Exception as e:
        result["config_error"] = str(e)

print(json.dumps(result))
PYEOF
)

# ── 4. Count new screenshots ──────────────────────────────────────────────────
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

# ── 5. Check presentation notes file ──────────────────────────────────────────
NOTES_EXISTS="false"
NOTES_HAS_NEW_YORK="false"
NOTES_HAS_ORION="false"
NOTES_HAS_BORTLE="false"
NOTES_SIZE=0

if [ -f "$PRESENTATION_NOTES" ]; then
    NOTES_EXISTS="true"
    NOTES_SIZE=$(wc -c < "$PRESENTATION_NOTES" 2>/dev/null || echo "0")
    if grep -qi "New York" "$PRESENTATION_NOTES" 2>/dev/null; then
        NOTES_HAS_NEW_YORK="true"
    fi
    if grep -qi "Orion" "$PRESENTATION_NOTES" 2>/dev/null; then
        NOTES_HAS_ORION="true"
    fi
    if grep -qi "Bortle" "$PRESENTATION_NOTES" 2>/dev/null; then
        NOTES_HAS_BORTLE="true"
    fi
fi

# ── 6. Write result JSON ──────────────────────────────────────────────────────
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
    "flag_constellation_drawing": config.get("flag_constellation_drawing"),
    "flag_light_pollution_database": config.get("flag_light_pollution_database"),
    "light_pollution_luminance": config.get("light_pollution_luminance"),
    "new_screenshot_count": $FINAL_SS_COUNT,
    "notes_exists": "$NOTES_EXISTS" == "true",
    "notes_size_bytes": $NOTES_SIZE,
    "notes_has_new_york": "$NOTES_HAS_NEW_YORK" == "true",
    "notes_has_orion": "$NOTES_HAS_ORION" == "true",
    "notes_has_bortle": "$NOTES_HAS_BORTLE" == "true"
}

with open("/tmp/${TASK_NAME}_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/${TASK_NAME}_result.json 2>/dev/null || true

echo "=== Export Complete ==="
cat /tmp/${TASK_NAME}_result.json