#!/bin/bash
echo "=== Exporting precession_pole_star_demo result ==="

TASK_NAME="precession_pole_star_demo"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")
INITIAL_SS_COUNT=$(cat /tmp/${TASK_NAME}_initial_screenshot_count 2>/dev/null || echo "0")
SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
NOTES_PATH="/home/ga/Desktop/precession_notes.txt"

# ── 1. Take final screenshot before killing Stellarium ────────────────────────
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_end_screenshot.png 2>/dev/null || \
DISPLAY=:1 scrot /tmp/${TASK_NAME}_end_screenshot.png 2>/dev/null || true

# ── 2. Gracefully terminate Stellarium to flush config.ini ───────────────────
echo "Terminating Stellarium to save config..."
pkill -SIGTERM stellarium 2>/dev/null || true

# Wait for save and exit
for i in $(seq 1 15); do
    if ! pgrep stellarium > /dev/null 2>&1; then
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
    "flag_equatorial_grid": None, "flag_constellation_drawing": None,
    "preset_sky_time": None
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
        result["flag_atmosphere"] = get_bool('landscape', 'flag_atmosphere', 'true')
        result["flag_landscape"] = get_bool('landscape', 'flag_landscape', 'true')
        result["flag_equatorial_grid"] = get_bool('viewing', 'flag_equatorial_grid', 'false')
        result["flag_constellation_drawing"] = get_bool('viewing', 'flag_constellation_drawing', 'false')
        result["preset_sky_time"] = get_float('navigation', 'preset_sky_time')
    except Exception as e:
        result["error"] = str(e)

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

# ── 5. Check Lecture Notes ────────────────────────────────────────────────────
NOTES_EXISTS="false"
NOTES_HAS_THUBAN="false"
NOTES_HAS_PRECESSION="false"

if [ -f "$NOTES_PATH" ]; then
    NOTES_EXISTS="true"
    if grep -qi "thuban" "$NOTES_PATH" 2>/dev/null; then
        NOTES_HAS_THUBAN="true"
    fi
    if grep -qi "precession" "$NOTES_PATH" 2>/dev/null; then
        NOTES_HAS_PRECESSION="true"
    fi
fi

# ── 6. Write result JSON ──────────────────────────────────────────────────────
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
    "flag_equatorial_grid": config.get("flag_equatorial_grid"),
    "flag_constellation_drawing": config.get("flag_constellation_drawing"),
    "preset_sky_time": config.get("preset_sky_time"),
    "new_screenshot_count": $FINAL_SS_COUNT,
    "notes_exists": $NOTES_EXISTS,
    "notes_has_thuban": $NOTES_HAS_THUBAN,
    "notes_has_precession": $NOTES_HAS_PRECESSION
}

with open("/tmp/${TASK_NAME}_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/${TASK_NAME}_result.json 2>/dev/null || true
echo "Export complete: /tmp/${TASK_NAME}_result.json"
cat /tmp/${TASK_NAME}_result.json