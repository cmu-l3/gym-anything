#!/bin/bash
echo "=== Exporting interplanetary_earth_observation result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

TASK_NAME="interplanetary_earth_observation"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")
INITIAL_SS_COUNT=$(cat /tmp/${TASK_NAME}_initial_screenshot_count 2>/dev/null || echo "0")
SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
NOTES_FILE="/home/ga/Desktop/cassini_exhibit.txt"
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

# ── 3. Parse config.ini with Python ──────────────────────────────────────────
CONFIG_JSON=$(python3 << 'PYEOF'
import configparser, json, os

config_path = "/home/ga/.stellarium/config.ini"
result = {
    "config_exists": False,
    "home_planet": "",
    "flag_atmosphere": None,
    "flag_landscape": None,
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

        # Planet
        planet1 = cfg.get('location_run_once', 'home_planet', fallback='')
        planet2 = cfg.get('init_location', 'home_planet', fallback='')
        planet3 = cfg.get('location_run_once', 'planet', fallback='')
        result["home_planet"] = planet1 or planet2 or planet3

        # Display flags
        result["flag_atmosphere"] = get_bool('landscape', 'flag_atmosphere', 'true')
        result["flag_landscape"] = get_bool('landscape', 'flag_landscape', 'true')

    except Exception as e:
        result["config_error"] = str(e)

print(json.dumps(result))
PYEOF
)

echo "Config parsed: $CONFIG_JSON"

# ── 4. Count new screenshots ─────────────────────────────────────────────────
CURRENT_SS_COUNT=$(ls "$SCREENSHOT_DIR" 2>/dev/null | wc -l)
NEW_SS_COUNT=$((CURRENT_SS_COUNT - INITIAL_SS_COUNT))

SS_NEW_BY_TIME=0
if [ -d "$SCREENSHOT_DIR" ]; then
    SS_NEW_BY_TIME=$(find "$SCREENSHOT_DIR" -newer /tmp/${TASK_NAME}_start_ts -type f 2>/dev/null | wc -l)
fi

# Use the higher of the two counts
if [ "$SS_NEW_BY_TIME" -gt "$NEW_SS_COUNT" ]; then
    FINAL_SS_COUNT="$SS_NEW_BY_TIME"
else
    FINAL_SS_COUNT="$NEW_SS_COUNT"
fi
echo "New screenshots: $FINAL_SS_COUNT"

# ── 5. Check notes file ───────────────────────────────────────────────
NOTES_EXISTS="false"
NOTES_CONTENT=""

if [ -f "$NOTES_FILE" ]; then
    NOTES_EXISTS="true"
    # Read up to 2000 chars, removing newlines and escaping quotes
    NOTES_CONTENT=$(head -c 2000 "$NOTES_FILE" | tr '\n' ' ' | sed 's/"/\\"/g' | sed 's/\\/\\\\/g')
fi

# ── 6. Write result JSON ──────────────────────────────────────────────────────
python3 << PYEOF
import json

config = json.loads('''$CONFIG_JSON''')

result = {
    "task_name": "$TASK_NAME",
    "task_start": $TASK_START,
    "config_exists": config.get("config_exists", False),
    "home_planet": config.get("home_planet", ""),
    "flag_atmosphere": config.get("flag_atmosphere"),
    "flag_landscape": config.get("flag_landscape"),
    "new_screenshot_count": $FINAL_SS_COUNT,
    "notes_exists": "$NOTES_EXISTS" == "true",
    "notes_content": "$NOTES_CONTENT"
}

with open("/tmp/${TASK_NAME}_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/${TASK_NAME}_result.json 2>/dev/null || true

echo "=== Export Complete ==="
cat /tmp/${TASK_NAME}_result.json