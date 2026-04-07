#!/bin/bash
echo "=== Exporting lunar_eclipse_event_planner result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

TASK_NAME="lunar_eclipse_event_planner"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")
INITIAL_SS_COUNT=$(cat /tmp/${TASK_NAME}_initial_ss_count 2>/dev/null || echo "0")
SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
GUIDE_PATH="/home/ga/Desktop/eclipse_event_guide.txt"
CONFIG_PATH="/home/ga/.stellarium/config.ini"

# ── 1. Take final screenshot before closing ──────────────────────────────────
take_screenshot /tmp/${TASK_NAME}_final.png

# ── 2. Gracefully terminate Stellarium to flush config.ini ───────────────────
echo "--- Terminating Stellarium to flush config ---"
pkill -SIGTERM stellarium 2>/dev/null || true

# Wait for clean exit
for i in $(seq 1 15); do
    if ! pgrep stellarium > /dev/null 2>&1; then
        echo "Stellarium exited after ${i}s"
        break
    fi
    sleep 1
done

# Force kill if hung
pkill -9 stellarium 2>/dev/null || true
sleep 2

# ── 3. Parse config.ini ──────────────────────────────────────────────────────
CONFIG_JSON=$(python3 << 'PYEOF'
import configparser, json, os

config_path = "/home/ga/.stellarium/config.ini"
result = {
    "config_exists": False,
    "lat_rad": None, "lon_rad": None, "alt_m": None,
    "flag_atmosphere": None, 
    "flag_azimuthal_grid": None,
    "flag_constellation_drawing": None,
    "flag_cardinal_points": None,
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
        
        result["flag_atmosphere"] = get_bool('landscape', 'flag_atmosphere', 'true')
        result["flag_azimuthal_grid"] = get_bool('viewing', 'flag_azimuthal_grid', 'false')
        result["flag_constellation_drawing"] = get_bool('viewing', 'flag_constellation_drawing', 'false')
        result["flag_cardinal_points"] = get_bool('landscape', 'flag_cardinal_points', 'true')
    except Exception as e:
        result["config_error"] = str(e)

print(json.dumps(result))
PYEOF
)

# ── 4. Evaluate Screenshots ──────────────────────────────────────────────────
CURRENT_SS_COUNT=$(ls "$SCREENSHOT_DIR" 2>/dev/null | wc -l)
NEW_SS_COUNT=$((CURRENT_SS_COUNT - INITIAL_SS_COUNT))

SS_NEW_BY_TIME=0
if [ -d "$SCREENSHOT_DIR" ]; then
    SS_NEW_BY_TIME=$(find "$SCREENSHOT_DIR" -type f -newer /tmp/${TASK_NAME}_start_ts 2>/dev/null | wc -l)
fi

FINAL_SS_COUNT=$(( NEW_SS_COUNT > SS_NEW_BY_TIME ? NEW_SS_COUNT : SS_NEW_BY_TIME ))

# ── 5. Evaluate Event Guide File ─────────────────────────────────────────────
GUIDE_EXISTS="false"
GUIDE_CREATED_DURING_TASK="false"
GUIDE_SIZE=0
HAS_NEW_YORK="false"
HAS_DATE="false"
HAS_TARGET="false"

if [ -f "$GUIDE_PATH" ]; then
    GUIDE_EXISTS="true"
    GUIDE_SIZE=$(stat -c %s "$GUIDE_PATH" 2>/dev/null || echo "0")
    
    FILE_MTIME=$(stat -c %Y "$GUIDE_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        GUIDE_CREATED_DURING_TASK="true"
    fi
    
    if grep -qi "New York\|NYC" "$GUIDE_PATH" 2>/dev/null; then
        HAS_NEW_YORK="true"
    fi
    
    if grep -qi "March 14\|Mar 14\|03/14/2025\|2025-03-14" "$GUIDE_PATH" 2>/dev/null; then
        HAS_DATE="true"
    fi
    
    if grep -qi "Moon\|Eclipse\|Lunar" "$GUIDE_PATH" 2>/dev/null; then
        HAS_TARGET="true"
    fi
fi

# ── 6. Write Export JSON ─────────────────────────────────────────────────────
python3 << PYEOF
import json

config = json.loads('''$CONFIG_JSON''')

result = {
    "task_start_ts": $TASK_START,
    "config": config,
    "screenshots": {
        "new_count": $FINAL_SS_COUNT
    },
    "guide_file": {
        "exists": $GUIDE_EXISTS,
        "created_during_task": $GUIDE_CREATED_DURING_TASK,
        "size_bytes": $GUIDE_SIZE,
        "has_new_york": $HAS_NEW_YORK,
        "has_date": $HAS_DATE,
        "has_target": $HAS_TARGET
    }
}

with open('/tmp/${TASK_NAME}_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/${TASK_NAME}_result.json 2>/dev/null || true
echo "Export complete. Result saved to /tmp/${TASK_NAME}_result.json"