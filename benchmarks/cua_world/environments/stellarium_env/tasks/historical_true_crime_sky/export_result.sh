#!/bin/bash
echo "=== Exporting historical_true_crime_sky result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

TASK_NAME="historical_true_crime_sky"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")
INITIAL_SS_COUNT=$(cat /tmp/${TASK_NAME}_initial_screenshot_count 2>/dev/null || echo "0")
SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
NOTES_FILE="/home/ga/Desktop/whitechapel_moon.txt"

# ── 1. Take final screenshot before killing application ───────────────────────
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
    "flag_atmosphere": None, "flag_landscape": None,
    "flag_azimuthal_grid": None, "flag_cardinal_points": None,
    "preset_sky_time": None, "startup_time_mode": None
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
        result["flag_cardinal_points"] = get_bool('landscape', 'flag_cardinal_points', 'false')
        result["flag_azimuthal_grid"] = get_bool('viewing', 'flag_azimuthal_grid', 'false')
        
        result["preset_sky_time"] = get_float('navigation', 'preset_sky_time', 0.0)
        try:
            result["startup_time_mode"] = cfg.get('navigation', 'startup_time_mode')
        except:
            pass

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

FINAL_SS_COUNT=$(( SS_NEW_BY_TIME > NEW_SS_COUNT ? SS_NEW_BY_TIME : NEW_SS_COUNT ))

# ── 5. Extract Notes File Content ─────────────────────────────────────────────
NOTES_EXISTS="false"
NOTES_CONTENT=""

if [ -f "$NOTES_FILE" ]; then
    NOTES_EXISTS="true"
    # Read the first 1000 chars of notes file (to avoid massive json if abuse)
    NOTES_CONTENT=$(head -c 1000 "$NOTES_FILE" | tr -d '\000-\031' | sed 's/"/\\"/g')
fi

# ── 6. Write result JSON ──────────────────────────────────────────────────────
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "config_exists": $(echo "$CONFIG_JSON" | grep -o '"config_exists": [a-z]*' | cut -d' ' -f2),
    "lat_rad": $(echo "$CONFIG_JSON" | grep -o '"lat_rad": [^,]*' | cut -d' ' -f2),
    "lon_rad": $(echo "$CONFIG_JSON" | grep -o '"lon_rad": [^,]*' | cut -d' ' -f2),
    "flag_atmosphere": $(echo "$CONFIG_JSON" | grep -o '"flag_atmosphere": [a-z]*' | cut -d' ' -f2),
    "flag_landscape": $(echo "$CONFIG_JSON" | grep -o '"flag_landscape": [a-z]*' | cut -d' ' -f2),
    "flag_azimuthal_grid": $(echo "$CONFIG_JSON" | grep -o '"flag_azimuthal_grid": [a-z]*' | cut -d' ' -f2),
    "flag_cardinal_points": $(echo "$CONFIG_JSON" | grep -o '"flag_cardinal_points": [a-z]*' | cut -d' ' -f2),
    "preset_sky_time": $(echo "$CONFIG_JSON" | grep -o '"preset_sky_time": [^,}]*' | cut -d' ' -f2),
    "new_screenshot_count": $FINAL_SS_COUNT,
    "notes_exists": $NOTES_EXISTS,
    "notes_content": "$NOTES_CONTENT",
    "export_timestamp": "$(date +%s)"
}
EOF

rm -f /tmp/${TASK_NAME}_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/${TASK_NAME}_result.json
chmod 666 /tmp/${TASK_NAME}_result.json
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="
cat /tmp/${TASK_NAME}_result.json