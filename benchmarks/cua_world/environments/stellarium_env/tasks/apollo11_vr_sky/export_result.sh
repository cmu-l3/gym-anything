#!/bin/bash
echo "=== Exporting apollo11_vr_sky result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

TASK_NAME="apollo11_vr_sky"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")
INITIAL_SS_COUNT=$(cat /tmp/${TASK_NAME}_initial_screenshot_count 2>/dev/null || echo "0")
SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
NOTES_FILE="/home/ga/Desktop/apollo_vr_reference.txt"

# ── 1. Take final screenshot (while Stellarium is running) ────────────────────
sleep 2
take_screenshot /tmp/${TASK_NAME}_end_screenshot.png

# ── 2. Gracefully terminate Stellarium to force config.ini save ───────────────
echo "--- Terminating Stellarium to flush config ---"
pkill -SIGTERM stellarium 2>/dev/null || true

# Wait for cleanly exit to ensure config flushes
for i in $(seq 1 15); do
    if ! pgrep stellarium > /dev/null 2>&1; then
        echo "Stellarium exited gracefully"
        break
    fi
    sleep 1
done

pkill -9 stellarium 2>/dev/null || true
sleep 2

# ── 3. Parse config.ini with Python ───────────────────────────────────────────
CONFIG_JSON=$(python3 << 'PYEOF'
import configparser, json, os

config_path = "/home/ga/.stellarium/config.ini"
result = {
    "config_exists": False,
    "home_planet": "Earth",
    "lat_rad": 0.0,
    "lon_rad": 0.0,
    "flag_atmosphere": True,
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

        result["home_planet"] = cfg.get('location_run_once', 'home_planet', fallback='Earth')
        
        try:
            result["lat_rad"] = float(cfg.get('location_run_once', 'latitude'))
        except: pass
        
        try:
            result["lon_rad"] = float(cfg.get('location_run_once', 'longitude'))
        except: pass

        result["flag_atmosphere"] = get_bool('landscape', 'flag_atmosphere', 'true')

    except Exception as e:
        result["config_error"] = str(e)

print(json.dumps(result))
PYEOF
)

# ── 4. Evaluate Screenshots ───────────────────────────────────────────────────
CURRENT_SS_COUNT=$(ls -1 "$SCREENSHOT_DIR" 2>/dev/null | wc -l)
NEW_SS_COUNT=$((CURRENT_SS_COUNT - INITIAL_SS_COUNT))

SS_NEW_BY_TIME=0
if [ -d "$SCREENSHOT_DIR" ]; then
    SS_NEW_BY_TIME=$(find "$SCREENSHOT_DIR" -newer /tmp/${TASK_NAME}_start_ts -type f 2>/dev/null | wc -l)
fi

FINAL_SS_COUNT=$(( SS_NEW_BY_TIME > NEW_SS_COUNT ? SS_NEW_BY_TIME : NEW_SS_COUNT ))
echo "Screenshots captured during task: $FINAL_SS_COUNT"

# ── 5. Check Reference Notes File ─────────────────────────────────────────────
NOTES_EXISTS="false"
NOTES_HAS_MOON="false"
NOTES_HAS_1969="false"
NOTES_HAS_EARTH_SUN="false"

if [ -f "$NOTES_FILE" ]; then
    NOTES_EXISTS="true"
    
    # Check for "Moon", "Lunar", or "Tranquility"
    if grep -qi "Moon\|Lunar\|Tranquility\|Apollo" "$NOTES_FILE" 2>/dev/null; then
        NOTES_HAS_MOON="true"
    fi
    
    # Check for the historical year
    if grep -q "1969" "$NOTES_FILE" 2>/dev/null; then
        NOTES_HAS_1969="true"
    fi
    
    # Check if Earth/Sun are mentioned
    if grep -qi "Earth" "$NOTES_FILE" 2>/dev/null && grep -qi "Sun" "$NOTES_FILE" 2>/dev/null; then
        NOTES_HAS_EARTH_SUN="true"
    fi
fi

# ── 6. Write Export JSON ──────────────────────────────────────────────────────
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 << PYEOF > "$TEMP_JSON"
import json

config = json.loads('''$CONFIG_JSON''')

result = {
    "task_start": $TASK_START,
    "config_exists": config.get("config_exists", False),
    "home_planet": config.get("home_planet", "Earth"),
    "lat_rad": config.get("lat_rad", 0.0),
    "lon_rad": config.get("lon_rad", 0.0),
    "flag_atmosphere": config.get("flag_atmosphere", True),
    "new_screenshot_count": $FINAL_SS_COUNT,
    "notes_exists": $NOTES_EXISTS,
    "notes_has_moon": $NOTES_HAS_MOON,
    "notes_has_1969": $NOTES_HAS_1969,
    "notes_has_earth_sun": $NOTES_HAS_EARTH_SUN
}

print(json.dumps(result, indent=2))
PYEOF

rm -f /tmp/${TASK_NAME}_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/${TASK_NAME}_result.json
chmod 666 /tmp/${TASK_NAME}_result.json
rm -f "$TEMP_JSON"

echo "Export JSON written to /tmp/${TASK_NAME}_result.json"
cat /tmp/${TASK_NAME}_result.json