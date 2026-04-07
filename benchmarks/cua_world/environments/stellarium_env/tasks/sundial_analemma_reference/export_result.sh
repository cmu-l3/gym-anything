#!/bin/bash
echo "=== Exporting sundial_analemma_reference result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

TASK_NAME="sundial_analemma_reference"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")
INITIAL_SS_COUNT=$(cat /tmp/${TASK_NAME}_initial_screenshot_count 2>/dev/null || echo "0")
SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
REFERENCE_NOTES="/home/ga/Desktop/sundial_reference.txt"
CONFIG_PATH="/home/ga/.stellarium/config.ini"

# ── 1. Take final screenshot (while Stellarium is still running) ──────────────
sleep 2
take_screenshot /tmp/${TASK_NAME}_end_screenshot.png

# ── 2. Gracefully terminate Stellarium to force config.ini save ───────────────
echo "--- Terminating Stellarium to flush config ---"
pkill -SIGTERM stellarium 2>/dev/null || true

# Wait for Stellarium to exit cleanly (config is saved on exit)
for i in $(seq 1 15); do
    if ! pgrep stellarium > /dev/null 2>&1; then
        echo "Stellarium exited after ${i}s"
        break
    fi
    sleep 1
done

# Force kill if still running
pkill -9 stellarium 2>/dev/null || true
sleep 2

# ── 3. Parse config.ini with Python ───────────────────────────────────────────
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
    "flag_azimuthal_grid": None,
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

        # Location
        result["lat_rad"] = get_float('location_run_once', 'latitude', 0.0)
        result["lon_rad"] = get_float('location_run_once', 'longitude', 0.0)
        result["alt_m"] = get_float('location_run_once', 'altitude', 0.0)

        # Display flags
        result["flag_atmosphere"] = get_bool('landscape', 'flag_atmosphere', 'true')
        result["flag_landscape"] = get_bool('landscape', 'flag_landscape', 'true')
        
        # Some versions put cardinal points in viewing, some in landscape
        cardinal_landscape = get_bool('landscape', 'flag_cardinal_points', 'not_found')
        if cardinal_landscape != 'not_found' and type(cardinal_landscape) == bool:
            result["flag_cardinal_points"] = cardinal_landscape
        else:
            result["flag_cardinal_points"] = get_bool('viewing', 'flag_cardinal_points', 'false')
            
        result["flag_azimuthal_grid"] = get_bool('viewing', 'flag_azimuthal_grid', 'false')

    except Exception as e:
        result["config_error"] = str(e)

print(json.dumps(result))
PYEOF
)

# ── 4. Count new screenshots ──────────────────────────────────────────────────
CURRENT_SS_COUNT=$(ls "$SCREENSHOT_DIR" 2>/dev/null | wc -l)
NEW_SS_COUNT=$((CURRENT_SS_COUNT - INITIAL_SS_COUNT))
echo "Screenshots: initial=$INITIAL_SS_COUNT, current=$CURRENT_SS_COUNT, new=$NEW_SS_COUNT"

SS_NEW_BY_TIME=0
if [ -d "$SCREENSHOT_DIR" ]; then
    SS_NEW_BY_TIME=$(find "$SCREENSHOT_DIR" -newer /tmp/${TASK_NAME}_start_ts -type f 2>/dev/null | wc -l)
fi
echo "Screenshots newer than task start: $SS_NEW_BY_TIME"

# Use the highest count safely found
FINAL_SS_COUNT="$NEW_SS_COUNT"
if [ "$SS_NEW_BY_TIME" -gt "$NEW_SS_COUNT" ]; then
    FINAL_SS_COUNT="$SS_NEW_BY_TIME"
fi

# ── 5. Check reference notes file ─────────────────────────────────────────────
NOTES_EXISTS="false"
NOTES_HAS_DOMAIN="false"
NOTES_HAS_DATE="false"
NOTES_SIZE=0

if [ -f "$REFERENCE_NOTES" ]; then
    NOTES_EXISTS="true"
    NOTES_SIZE=$(wc -c < "$REFERENCE_NOTES" 2>/dev/null || echo "0")

    if grep -qi "jantar mantar\|sundial\|samrat yantra" "$REFERENCE_NOTES" 2>/dev/null; then
        NOTES_HAS_DOMAIN="true"
    fi

    if grep -qi "equinox\|solstice\|march\|june\|september\|december" "$REFERENCE_NOTES" 2>/dev/null; then
        NOTES_HAS_DATE="true"
    fi
fi

# ── 6. Write final result JSON ────────────────────────────────────────────────
python3 << PYEOF
import json

config = json.loads('''$CONFIG_JSON''')

result = {
    "task_name": "$TASK_NAME",
    "task_start": $TASK_START,
    "config_exists": config.get("config_exists", False),
    "lat_rad": config.get("lat_rad"),
    "lon_rad": config.get("lon_rad"),
    "alt_m": config.get("alt_m"),
    "flag_atmosphere": config.get("flag_atmosphere"),
    "flag_landscape": config.get("flag_landscape"),
    "flag_azimuthal_grid": config.get("flag_azimuthal_grid"),
    "flag_cardinal_points": config.get("flag_cardinal_points"),
    "new_screenshot_count": int("$FINAL_SS_COUNT"),
    "notes_exists": "$NOTES_EXISTS" == "true",
    "notes_has_domain": "$NOTES_HAS_DOMAIN" == "true",
    "notes_has_date": "$NOTES_HAS_DATE" == "true",
    "notes_size_bytes": int("$NOTES_SIZE")
}

with open("/tmp/${TASK_NAME}_result.json", "w") as f:
    json.dump(result, f, indent=4)
PYEOF

chmod 666 /tmp/${TASK_NAME}_result.json 2>/dev/null || true

echo "Result saved to /tmp/${TASK_NAME}_result.json"
cat /tmp/${TASK_NAME}_result.json
echo "=== Export complete ==="