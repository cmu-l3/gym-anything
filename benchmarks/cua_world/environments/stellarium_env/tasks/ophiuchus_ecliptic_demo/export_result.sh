#!/bin/bash
echo "=== Exporting ophiuchus_ecliptic_demo result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

TASK_NAME="ophiuchus_ecliptic_demo"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")
INITIAL_SS_COUNT=$(cat /tmp/${TASK_NAME}_initial_screenshot_count 2>/dev/null || echo "0")
SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
SCRIPT_FILE="/home/ga/Desktop/ophiuchus_script.txt"
CONFIG_PATH="/home/ga/.stellarium/config.ini"

# 1. Take final screenshot
sleep 2
take_screenshot /tmp/${TASK_NAME}_end_screenshot.png

# 2. Terminate Stellarium gracefully to flush config
pkill -SIGTERM stellarium 2>/dev/null || true
for i in $(seq 1 15); do
    if ! pgrep stellarium > /dev/null 2>&1; then
        break
    fi
    sleep 1
done
pkill -9 stellarium 2>/dev/null || true
sleep 2

# 3. Parse config.ini state
CONFIG_JSON=$(python3 << 'PYEOF'
import configparser, json, os

config_path = "/home/ga/.stellarium/config.ini"
result = {
    "config_exists": False,
    "lat_rad": None, "lon_rad": None,
    "flag_atmosphere": None,
    "flag_constellation_boundaries": None,
    "flag_constellation_name": None,
    "flag_ecliptic_line": None,
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
        
        # Check potential flag keys across sections
        b1 = get_bool('viewing', 'flag_constellation_boundaries', 'false')
        b2 = get_bool('stars', 'flag_constellation_boundaries', 'false')
        result["flag_constellation_boundaries"] = b1 or b2

        n1 = get_bool('viewing', 'flag_constellation_name', 'false')
        n2 = get_bool('stars', 'flag_constellation_name', 'false')
        result["flag_constellation_name"] = n1 or n2
        
        e1 = get_bool('viewing', 'flag_ecliptic_line', 'false')
        e2 = get_bool('viewing', 'flag_ecliptic_of_date', 'false')
        result["flag_ecliptic_line"] = e1 or e2
    except Exception as e:
        result["config_error"] = str(e)

print(json.dumps(result))
PYEOF
)

# 4. Check screenshot count
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

# 5. Check script content
SCRIPT_EXISTS="false"
SCRIPT_HAS_OPHIUCHUS="false"
SCRIPT_HAS_SUN="false"
SCRIPT_HAS_ECLIPTIC="false"
SCRIPT_HAS_DATE="false"

if [ -f "$SCRIPT_FILE" ]; then
    SCRIPT_EXISTS="true"
    
    if grep -qi "Ophiuchus" "$SCRIPT_FILE" 2>/dev/null; then SCRIPT_HAS_OPHIUCHUS="true"; fi
    if grep -qi "Sun" "$SCRIPT_FILE" 2>/dev/null; then SCRIPT_HAS_SUN="true"; fi
    if grep -qi "Ecliptic" "$SCRIPT_FILE" 2>/dev/null; then SCRIPT_HAS_ECLIPTIC="true"; fi
    if grep -qi "Nov" "$SCRIPT_FILE" 2>/dev/null || grep -qi "11/30" "$SCRIPT_FILE" 2>/dev/null || grep -qi "November 30" "$SCRIPT_FILE" 2>/dev/null; then
        SCRIPT_HAS_DATE="true"
    fi
fi

# 6. Save exported metrics
python3 << PYEOF
import json

config = json.loads('''$CONFIG_JSON''')

result = {
    "task_start": $TASK_START,
    "config_exists": config.get("config_exists", False),
    "lat_rad": config.get("lat_rad"),
    "lon_rad": config.get("lon_rad"),
    "flag_atmosphere": config.get("flag_atmosphere"),
    "flag_constellation_boundaries": config.get("flag_constellation_boundaries"),
    "flag_constellation_name": config.get("flag_constellation_name"),
    "flag_ecliptic_line": config.get("flag_ecliptic_line"),
    "new_screenshot_count": $FINAL_SS_COUNT,
    "script_exists": $SCRIPT_EXISTS,
    "script_has_ophiuchus": $SCRIPT_HAS_OPHIUCHUS,
    "script_has_sun": $SCRIPT_HAS_SUN,
    "script_has_ecliptic": $SCRIPT_HAS_ECLIPTIC,
    "script_has_date": $SCRIPT_HAS_DATE
}

with open('/tmp/${TASK_NAME}_result.json', 'w') as f:
    json.dump(result, f)
PYEOF

chmod 666 /tmp/${TASK_NAME}_result.json
echo "Result exported to /tmp/${TASK_NAME}_result.json"