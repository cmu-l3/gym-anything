#!/bin/bash
echo "=== Exporting tombaugh_pluto_discovery result ==="

TASK_NAME="tombaugh_pluto_discovery"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")
INITIAL_SS_COUNT=$(cat /tmp/${TASK_NAME}_initial_screenshot_count 2>/dev/null || echo "0")
SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
EXHIBIT_NOTES="/home/ga/Desktop/tombaugh_exhibit.txt"

# ── 1. Take final desktop screenshot ──────────────────────────────────────────
DISPLAY=:1 scrot /tmp/${TASK_NAME}_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/${TASK_NAME}_end_screenshot.png 2>/dev/null || true

# ── 2. Gracefully terminate Stellarium to flush config.ini ───────────────────
echo "--- Terminating Stellarium to flush config ---"
pkill -SIGTERM stellarium 2>/dev/null || true

# Wait for Stellarium to exit cleanly (config is saved on exit)
for i in $(seq 1 15); do
    if ! pgrep stellarium > /dev/null 2>&1; then
        echo "Stellarium exited gracefully."
        break
    fi
    sleep 1
done

# Force kill if still running
pkill -9 stellarium 2>/dev/null || true
sleep 1

# ── 3. Parse config.ini state ─────────────────────────────────────────────────
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
    "flag_equatorial_grid": None,
    "flag_nebula": None,
    "preset_sky_time": None,
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
        result["flag_equatorial_grid"] = get_bool('viewing', 'flag_equatorial_grid', 'false')
        
        # Stellarium sometimes stores nebula flag in astrocalc or viewing
        result["flag_nebula"] = get_bool('astrocalc', 'flag_nebula', 'true')

        result["preset_sky_time"] = get_float('navigation', 'preset_sky_time', 2451545.0)

    except Exception as e:
        result["config_error"] = str(e)

print(json.dumps(result))
PYEOF
)

# ── 4. Check Screenshots ──────────────────────────────────────────────────────
CURRENT_SS_COUNT=$(ls -1 "$SCREENSHOT_DIR" 2>/dev/null | wc -l)
NEW_SS_COUNT=$((CURRENT_SS_COUNT - INITIAL_SS_COUNT))

SS_NEW_BY_TIME=0
if [ -d "$SCREENSHOT_DIR" ]; then
    SS_NEW_BY_TIME=$(find "$SCREENSHOT_DIR" -newer /tmp/${TASK_NAME}_start_ts -type f -name "*.png" 2>/dev/null | wc -l)
fi

# Use highest count
if [ "$SS_NEW_BY_TIME" -gt "$NEW_SS_COUNT" ]; then
    FINAL_SS_COUNT="$SS_NEW_BY_TIME"
else
    FINAL_SS_COUNT="$NEW_SS_COUNT"
fi

# ── 5. Evaluate Text Document ─────────────────────────────────────────────────
DOC_EXISTS="false"
CREATED_DURING_TASK="false"
HAS_JAN23="false"
HAS_JAN29="false"
HAS_1930="false"
HAS_PLUTO="false"
HAS_STAR="false"

if [ -f "$EXHIBIT_NOTES" ]; then
    DOC_EXISTS="true"
    
    DOC_MTIME=$(stat -c %Y "$EXHIBIT_NOTES" 2>/dev/null || echo "0")
    if [ "$DOC_MTIME" -ge "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi

    grep -qi "Jan.*23\|23.*Jan" "$EXHIBIT_NOTES" && HAS_JAN23="true"
    grep -qi "Jan.*29\|29.*Jan" "$EXHIBIT_NOTES" && HAS_JAN29="true"
    grep -qi "1930" "$EXHIBIT_NOTES" && HAS_1930="true"
    grep -qi "Pluto" "$EXHIBIT_NOTES" && HAS_PLUTO="true"
    grep -qi "Wasat\|Gemini" "$EXHIBIT_NOTES" && HAS_STAR="true"
fi

# ── 6. Assemble Final JSON Result ─────────────────────────────────────────────
python3 << PYEOF
import json

config = json.loads('''$CONFIG_JSON''')

result = {
    "task_start": $TASK_START,
    "config": config,
    "screenshots": {
        "new_count": $FINAL_SS_COUNT
    },
    "document": {
        "exists": $DOC_EXISTS,
        "created_during_task": $CREATED_DURING_TASK,
        "has_jan23": $HAS_JAN23,
        "has_jan29": $HAS_JAN29,
        "has_1930": $HAS_1930,
        "has_pluto": $HAS_PLUTO,
        "has_star": $HAS_STAR
    }
}

with open("/tmp/${TASK_NAME}_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/${TASK_NAME}_result.json 2>/dev/null || true
echo "Export Complete. Result saved to /tmp/${TASK_NAME}_result.json"
cat /tmp/${TASK_NAME}_result.json