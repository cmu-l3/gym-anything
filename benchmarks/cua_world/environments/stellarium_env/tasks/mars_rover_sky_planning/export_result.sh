#!/bin/bash
echo "=== Exporting mars_rover_sky_planning result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

TASK_NAME="mars_rover_sky_planning"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")
INITIAL_SS_COUNT=$(cat /tmp/${TASK_NAME}_initial_screenshot_count 2>/dev/null || echo "0")
SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
NOTES_PATH="/home/ga/Desktop/mars_sky_notes.txt"

# ── 1. Take final screenshot before killing Stellarium ────────────────────────
sleep 2
take_screenshot /tmp/${TASK_NAME}_end_screenshot.png

# ── 2. Gracefully terminate Stellarium to flush config.ini ───────────────────
echo "--- Terminating Stellarium to flush config ---"
pkill -SIGTERM stellarium 2>/dev/null || true

for i in $(seq 1 15); do
    if ! pgrep stellarium > /dev/null 2>&1; then
        echo "Stellarium exited cleanly after ${i}s"
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
    "planet": None,
    "lat_rad": None,
    "lon_rad": None,
    "alt_m": None,
    "flag_atmosphere": None,
    "flag_landscape": None,
    "flag_constellation_drawing": None,
    "flag_constellation_name": None,
    "flag_planets_labels": None,
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

        def get_str(section, key, default=None):
            try:
                return cfg.get(section, key)
            except:
                return default

        result["planet"] = get_str('location_run_once', 'planet', 'Earth')
        
        # Stellarium sometimes renames the key or drops home_planet, check 'planet'
        if not result["planet"] or result["planet"].lower() == "earth":
            home_planet = get_str('location_run_once', 'home_planet', '')
            if home_planet:
                result["planet"] = home_planet

        result["lat_rad"] = get_float('location_run_once', 'latitude', 0.0)
        result["lon_rad"] = get_float('location_run_once', 'longitude', 0.0)
        result["alt_m"] = get_float('location_run_once', 'altitude', 0.0)
        
        result["flag_atmosphere"] = get_bool('landscape', 'flag_atmosphere', 'true')
        result["flag_landscape"] = get_bool('landscape', 'flag_landscape', 'true')
        result["flag_constellation_drawing"] = get_bool('viewing', 'flag_constellation_drawing', 'false')
        result["flag_constellation_name"] = get_bool('viewing', 'flag_constellation_name', 'false')
        
        # Planet labels could be flag_planets_hints or flag_planets_labels
        p_hints = get_bool('astro', 'flag_planets_hints', 'false')
        p_labels = get_bool('viewing', 'flag_planets_labels', 'false')
        p_hints_v = get_bool('viewing', 'flag_planets_hints', 'false')
        result["flag_planets_labels"] = p_hints or p_labels or p_hints_v

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

# ── 5. Check notes file ───────────────────────────────────────────────────────
NOTES_EXISTS="false"
NOTES_HAS_MARS="false"
NOTES_HAS_EARTH_OR_SATURN="false"

if [ -f "$NOTES_PATH" ]; then
    NOTES_EXISTS="true"
    if grep -qi "Mars" "$NOTES_PATH" 2>/dev/null; then
        NOTES_HAS_MARS="true"
    fi
    if grep -qi "Earth\|Saturn" "$NOTES_PATH" 2>/dev/null; then
        NOTES_HAS_EARTH_OR_SATURN="true"
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
    "planet": config.get("planet"),
    "lat_rad": config.get("lat_rad"),
    "lon_rad": config.get("lon_rad"),
    "alt_m": config.get("alt_m"),
    "flag_atmosphere": config.get("flag_atmosphere"),
    "flag_landscape": config.get("flag_landscape"),
    "flag_constellation_drawing": config.get("flag_constellation_drawing"),
    "flag_constellation_name": config.get("flag_constellation_name"),
    "flag_planets_labels": config.get("flag_planets_labels"),
    "new_screenshot_count": $FINAL_SS_COUNT,
    "notes_exists": "$NOTES_EXISTS" == "true",
    "notes_has_mars": "$NOTES_HAS_MARS" == "true",
    "notes_has_earth_or_saturn": "$NOTES_HAS_EARTH_OR_SATURN" == "true"
}

with open("/tmp/${TASK_NAME}_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

cat /tmp/${TASK_NAME}_result.json
echo "=== Export Complete ==="