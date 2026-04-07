#!/bin/bash
echo "=== Exporting sappho_poem_dating result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

TASK_NAME="sappho_poem_dating"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")
INITIAL_SS_COUNT=$(cat /tmp/${TASK_NAME}_initial_screenshot_count 2>/dev/null || echo "0")
SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
NOTES_PATH="/home/ga/Desktop/sappho_lecture.txt"

# 1. Take final screenshot
sleep 2
take_screenshot /tmp/${TASK_NAME}_end_screenshot.png

# 2. Terminate Stellarium gracefully
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
# Stellarium was configured to NOT save on exit, so this directly verifies
# if the agent clicked the "Save settings" button in the configuration menu.
CONFIG_JSON=$(python3 << 'PYEOF'
import configparser, json, os

config_path = "/home/ga/.stellarium/config.ini"
result = {
    "config_exists": False,
    "lat_rad": None,
    "lon_rad": None,
    "flag_atmosphere": None,
    "flag_azimuthal_grid": None,
    "flag_constellation_art": None,
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
        result["flag_azimuthal_grid"] = get_bool('viewing', 'flag_azimuthal_grid', 'false')
        result["flag_constellation_art"] = get_bool('viewing', 'flag_constellation_art', 'false')
    except Exception as e:
        result["config_error"] = str(e)

print(json.dumps(result))
PYEOF
)

# 4. Check screenshots (newer than task start to prevent gaming)
CURRENT_SS_COUNT=$(ls "$SCREENSHOT_DIR" 2>/dev/null | wc -l)
NEW_SS_COUNT=$((CURRENT_SS_COUNT - INITIAL_SS_COUNT))
SS_NEW_BY_TIME=0
if [ -d "$SCREENSHOT_DIR" ]; then
    SS_NEW_BY_TIME=$(find "$SCREENSHOT_DIR" -newer /tmp/${TASK_NAME}_start_ts -type f 2>/dev/null | wc -l)
fi

# Take highest credible count
if [ "$SS_NEW_BY_TIME" -gt "$NEW_SS_COUNT" ]; then
    FINAL_SS_COUNT="$SS_NEW_BY_TIME"
else
    FINAL_SS_COUNT="$NEW_SS_COUNT"
fi

# 5. Check lecture notes file
NOTES_EXISTS="false"
HAS_SAPPHO="false"
HAS_LESBOS="false"
HAS_570="false"
HAS_PLEIADES="false"

if [ -f "$NOTES_PATH" ]; then
    NOTES_EXISTS="true"
    if grep -qi "sappho" "$NOTES_PATH" 2>/dev/null; then HAS_SAPPHO="true"; fi
    if grep -qi "lesbos" "$NOTES_PATH" 2>/dev/null; then HAS_LESBOS="true"; fi
    if grep -qi "570" "$NOTES_PATH" 2>/dev/null; then HAS_570="true"; fi
    if grep -qi "pleiades\|m45" "$NOTES_PATH" 2>/dev/null; then HAS_PLEIADES="true"; fi
fi

# 6. Write result JSON
python3 << PYEOF
import json

config = json.loads('''$CONFIG_JSON''')

result = {
    "task_name": "$TASK_NAME",
    "task_start": $TASK_START,
    "config": config,
    "new_screenshot_count": $FINAL_SS_COUNT,
    "notes_exists": $NOTES_EXISTS,
    "notes_has_sappho": $HAS_SAPPHO,
    "notes_has_lesbos": $HAS_LESBOS,
    "notes_has_570": $HAS_570,
    "notes_has_pleiades": $HAS_PLEIADES
}

with open('/tmp/${TASK_NAME}_result.json', 'w') as f:
    json.dump(result, f)
PYEOF

chmod 666 /tmp/${TASK_NAME}_result.json 2>/dev/null || true
echo "Export complete: /tmp/${TASK_NAME}_result.json"