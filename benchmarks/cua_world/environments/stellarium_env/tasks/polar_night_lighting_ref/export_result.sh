#!/bin/bash
echo "=== Exporting polar_night_lighting_ref result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

TASK_NAME="polar_night_lighting_ref"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")
INITIAL_SS_COUNT=$(cat /tmp/${TASK_NAME}_initial_screenshot_count 2>/dev/null || echo "0")
SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
NOTES_FILE="/home/ga/Desktop/polar_night_lighting_notes.txt"
CONFIG_PATH="/home/ga/.stellarium/config.ini"

# ── 1. Take final screenshot before closing ───────────────────────────────────
sleep 2
take_screenshot /tmp/${TASK_NAME}_end_screenshot.png

# ── 2. Terminate Stellarium to force config save ──────────────────────────────
echo "--- Terminating Stellarium to flush config ---"
pkill -SIGTERM stellarium 2>/dev/null || true

for i in $(seq 1 15); do
    if ! pgrep stellarium > /dev/null 2>&1; then
        echo "Stellarium exited gracefully."
        break
    fi
    sleep 1
done

pkill -9 stellarium 2>/dev/null || true
sleep 2

# ── 3. Parse Stellarium config ────────────────────────────────────────────────
CONFIG_JSON=$(python3 << 'PYEOF'
import configparser, json, os

config_path = "/home/ga/.stellarium/config.ini"
result = {
    "config_exists": False,
    "lat_rad": None, "lon_rad": None, "alt_m": None,
    "flag_atmosphere": None, "flag_landscape": None,
    "flag_cardinal_points": None, "flag_constellation_drawing": None,
    "flag_constellation_name": None, "flag_azimuthal_grid": None,
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
        result["alt_m"] = get_float('location_run_once', 'altitude', 0.0)
        
        result["flag_atmosphere"] = get_bool('landscape', 'flag_atmosphere', 'true')
        result["flag_landscape"] = get_bool('landscape', 'flag_landscape', 'true')
        result["flag_cardinal_points"] = get_bool('landscape', 'flag_cardinal_points', 'false')
        
        result["flag_constellation_drawing"] = get_bool('viewing', 'flag_constellation_drawing', 'false')
        result["flag_constellation_name"] = get_bool('viewing', 'flag_constellation_name', 'false')
        result["flag_azimuthal_grid"] = get_bool('viewing', 'flag_azimuthal_grid', 'false')
        
    except Exception as e:
        result["config_error"] = str(e)

print(json.dumps(result))
PYEOF
)

# ── 4. Evaluate Screenshots ───────────────────────────────────────────────────
SS_NEW_BY_TIME=0
if [ -d "$SCREENSHOT_DIR" ]; then
    SS_NEW_BY_TIME=$(find "$SCREENSHOT_DIR" -newer /tmp/${TASK_NAME}_start_ts -type f 2>/dev/null | wc -l)
fi

# ── 5. Evaluate Notes File ────────────────────────────────────────────────────
NOTES_EXISTS="false"
NOTES_SIZE=0
NOTES_HAS_TROMSO="false"
NOTES_HAS_DATE="false"
NOTES_HAS_TARGETS="false"

if [ -f "$NOTES_FILE" ]; then
    NOTES_EXISTS="true"
    NOTES_SIZE=$(stat -c%s "$NOTES_FILE" 2>/dev/null || wc -c < "$NOTES_FILE" 2>/dev/null || echo "0")
    
    if grep -qi "tromso\|tromsø\|norway" "$NOTES_FILE" 2>/dev/null; then
        NOTES_HAS_TROMSO="true"
    fi
    if grep -qi "december\|21\|2023" "$NOTES_FILE" 2>/dev/null; then
        NOTES_HAS_DATE="true"
    fi
    if grep -qi "venus" "$NOTES_FILE" 2>/dev/null && grep -qi "polaris" "$NOTES_FILE" 2>/dev/null; then
        NOTES_HAS_TARGETS="true"
    fi
fi

# ── 6. Write Final JSON ───────────────────────────────────────────────────────
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
    "flag_cardinal_points": config.get("flag_cardinal_points"),
    "flag_constellation_drawing": config.get("flag_constellation_drawing"),
    "flag_constellation_name": config.get("flag_constellation_name"),
    "flag_azimuthal_grid": config.get("flag_azimuthal_grid"),
    "new_screenshot_count": $SS_NEW_BY_TIME,
    "notes_exists": $NOTES_EXISTS,
    "notes_size_bytes": $NOTES_SIZE,
    "notes_has_tromso": $NOTES_HAS_TROMSO,
    "notes_has_date": $NOTES_HAS_DATE,
    "notes_has_targets": $NOTES_HAS_TARGETS
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export completed successfully. Results written to /tmp/task_result.json"
cat /tmp/task_result.json