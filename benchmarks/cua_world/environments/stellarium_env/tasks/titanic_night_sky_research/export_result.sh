#!/bin/bash
echo "=== Exporting titanic_night_sky_research result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

TASK_NAME="titanic_night_sky_research"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")
INITIAL_SS_COUNT=$(cat /tmp/${TASK_NAME}_initial_screenshot_count 2>/dev/null || echo "0")
SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
NOTES_PATH="/home/ga/Desktop/titanic_sky_research.txt"

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

# Force kill if still lingering
pkill -9 stellarium 2>/dev/null || true
sleep 2

# ── 3. Parse config.ini ───────────────────────────────────────────────────────
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

        result["lat_rad"] = get_float('location_run_once', 'latitude')
        result["lon_rad"] = get_float('location_run_once', 'longitude')
        result["alt_m"] = get_float('location_run_once', 'altitude')
        
        result["flag_atmosphere"] = get_bool('landscape', 'flag_atmosphere')
        result["flag_landscape"] = get_bool('landscape', 'flag_landscape')
        result["flag_constellation_drawing"] = get_bool('viewing', 'flag_constellation_drawing')
        result["flag_constellation_name"] = get_bool('viewing', 'flag_constellation_name')
        
    except Exception as e:
        result["config_error"] = str(e)

print(json.dumps(result))
PYEOF
)

# ── 4. Count new screenshots ──────────────────────────────────────────────────
CURRENT_SS_COUNT=$(ls -1 "$SCREENSHOT_DIR" 2>/dev/null | wc -l)
NEW_SS_COUNT=$((CURRENT_SS_COUNT - INITIAL_SS_COUNT))
SS_NEW_BY_TIME=0
if [ -d "$SCREENSHOT_DIR" ]; then
    SS_NEW_BY_TIME=$(find "$SCREENSHOT_DIR" -newer /tmp/${TASK_NAME}_start_ts -type f 2>/dev/null | wc -l)
fi

# Use the highest valid count
if [ "$SS_NEW_BY_TIME" -gt "$NEW_SS_COUNT" ]; then
    FINAL_SS_COUNT="$SS_NEW_BY_TIME"
else
    FINAL_SS_COUNT="$NEW_SS_COUNT"
fi
echo "New screenshots captured: $FINAL_SS_COUNT"

# ── 5. Check Research Notes file ──────────────────────────────────────────────
NOTES_EXISTS="false"
NOTES_HAS_1912="false"
NOTES_HAS_MOON="false"
NOTES_SIZE=0

if [ -f "$NOTES_PATH" ]; then
    NOTES_EXISTS="true"
    NOTES_SIZE=$(stat -c%s "$NOTES_PATH" 2>/dev/null || echo "0")
    if grep -qi "1912" "$NOTES_PATH" 2>/dev/null; then
        NOTES_HAS_1912="true"
    fi
    if grep -qi "moon" "$NOTES_PATH" 2>/dev/null; then
        NOTES_HAS_MOON="true"
    fi
fi

echo "Research notes: exists=$NOTES_EXISTS, has_1912=$NOTES_HAS_1912, has_moon=$NOTES_HAS_MOON, size=$NOTES_SIZE bytes"

# ── 6. Write final result JSON ────────────────────────────────────────────────
python3 << PYEOF
import json
import os

config = json.loads('''$CONFIG_JSON''')

result = {
    "task_start": $TASK_START,
    "config_exists": config.get("config_exists", False),
    "lat_rad": config.get("lat_rad"),
    "lon_rad": config.get("lon_rad"),
    "alt_m": config.get("alt_m"),
    "flag_atmosphere": config.get("flag_atmosphere"),
    "flag_landscape": config.get("flag_landscape"),
    "flag_constellation_drawing": config.get("flag_constellation_drawing"),
    "flag_constellation_name": config.get("flag_constellation_name"),
    "new_screenshot_count": $FINAL_SS_COUNT,
    "notes_exists": "$NOTES_EXISTS" == "true",
    "notes_size_bytes": $NOTES_SIZE,
    "notes_has_1912": "$NOTES_HAS_1912" == "true",
    "notes_has_moon": "$NOTES_HAS_MOON" == "true"
}

output_path = "/tmp/${TASK_NAME}_result.json"
with open(output_path, 'w') as f:
    json.dump(result, f, indent=2)

os.chmod(output_path, 0o666)
PYEOF

echo "Result saved to /tmp/${TASK_NAME}_result.json"
cat /tmp/${TASK_NAME}_result.json
echo "=== Export Complete ==="