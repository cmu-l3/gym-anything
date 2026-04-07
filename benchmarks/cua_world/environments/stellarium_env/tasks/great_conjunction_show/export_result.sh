#!/bin/bash
echo "=== Exporting great_conjunction_show result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

TASK_NAME="great_conjunction_show"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")
INITIAL_SS_COUNT=$(cat /tmp/${TASK_NAME}_initial_screenshot_count 2>/dev/null || echo "0")
SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
SCRIPT_FILE="/home/ga/Desktop/planetarium_script.txt"
CONFIG_PATH="/home/ga/.stellarium/config.ini"

# ── 1. Take final screenshot before terminating Stellarium ───────────────────
sleep 2
take_screenshot /tmp/${TASK_NAME}_end_screenshot.png

# ── 2. Gracefully terminate Stellarium to flush config.ini ───────────────────
echo "--- Terminating Stellarium to flush config ---"
pkill -SIGTERM stellarium 2>/dev/null || true

# Wait for process to exit cleanly (flushes config)
for i in $(seq 1 15); do
    if ! pgrep stellarium > /dev/null 2>&1; then
        echo "Stellarium exited gracefully after ${i}s"
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
    "lat_rad": None, 
    "lon_rad": None,
    "flag_atmosphere": None, 
    "flag_landscape": None,
    "flag_constellation_drawing": None, 
    "flag_constellation_art": None,
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

        result["lat_rad"] = get_float('location_run_once', 'latitude', 0.0)
        result["lon_rad"] = get_float('location_run_once', 'longitude', 0.0)
        
        result["flag_atmosphere"] = get_bool('landscape', 'flag_atmosphere', 'true')
        result["flag_landscape"] = get_bool('landscape', 'flag_landscape', 'true')
        
        result["flag_constellation_drawing"] = get_bool('viewing', 'flag_constellation_drawing', 'false')
        result["flag_constellation_art"] = get_bool('viewing', 'flag_constellation_art', 'false')
        result["flag_constellation_name"] = get_bool('viewing', 'flag_constellation_name', 'false')
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
FINAL_SS_COUNT=$(( SS_NEW_BY_TIME > NEW_SS_COUNT ? SS_NEW_BY_TIME : NEW_SS_COUNT ))
echo "New screenshots: $FINAL_SS_COUNT"

# ── 5. Read Script File ───────────────────────────────────────────────────────
SCRIPT_EXISTS="false"
SCRIPT_CONTENT=""
if [ -f "$SCRIPT_FILE" ]; then
    SCRIPT_EXISTS="true"
    # Read up to 5000 characters and escape for JSON strings
    SCRIPT_CONTENT=$(head -c 5000 "$SCRIPT_FILE" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\n/\\n/g' -e 's/\r//g' | tr -d '\n')
fi

# ── 6. Write Export JSON ──────────────────────────────────────────────────────
cat > /tmp/${TASK_NAME}_result.json << EOF
{
    "task_name": "$TASK_NAME",
    "task_start": $TASK_START,
    "config_exists": $(echo "$CONFIG_JSON" | python3 -c 'import json, sys; print(str(json.load(sys.stdin).get("config_exists", False)).lower())'),
    "lat_rad": $(echo "$CONFIG_JSON" | python3 -c 'import json, sys; v=json.load(sys.stdin).get("lat_rad"); print("null" if v is None else v)'),
    "lon_rad": $(echo "$CONFIG_JSON" | python3 -c 'import json, sys; v=json.load(sys.stdin).get("lon_rad"); print("null" if v is None else v)'),
    "flag_atmosphere": $(echo "$CONFIG_JSON" | python3 -c 'import json, sys; print(str(json.load(sys.stdin).get("flag_atmosphere", False)).lower())'),
    "flag_landscape": $(echo "$CONFIG_JSON" | python3 -c 'import json, sys; print(str(json.load(sys.stdin).get("flag_landscape", False)).lower())'),
    "flag_constellation_art": $(echo "$CONFIG_JSON" | python3 -c 'import json, sys; print(str(json.load(sys.stdin).get("flag_constellation_art", False)).lower())'),
    "flag_constellation_drawing": $(echo "$CONFIG_JSON" | python3 -c 'import json, sys; print(str(json.load(sys.stdin).get("flag_constellation_drawing", False)).lower())'),
    "flag_constellation_name": $(echo "$CONFIG_JSON" | python3 -c 'import json, sys; print(str(json.load(sys.stdin).get("flag_constellation_name", False)).lower())'),
    "new_screenshot_count": $FINAL_SS_COUNT,
    "script_exists": $SCRIPT_EXISTS,
    "script_content": "$SCRIPT_CONTENT"
}
EOF

# Ensure world-readable for verification via copy_from_env
chmod 666 /tmp/${TASK_NAME}_result.json 2>/dev/null || sudo chmod 666 /tmp/${TASK_NAME}_result.json 2>/dev/null || true

echo "Export complete. Payload:"
cat /tmp/${TASK_NAME}_result.json