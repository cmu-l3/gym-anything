#!/bin/bash
echo "=== Exporting daytime_planetary_outreach result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

TASK_NAME="daytime_planetary_outreach"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")
INITIAL_SS_COUNT=$(cat /tmp/${TASK_NAME}_initial_screenshot_count 2>/dev/null || echo "0")
SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
PLAN_PATH="/home/ga/Desktop/daytime_outreach_plan.txt"
CONFIG_PATH="/home/ga/.stellarium/config.ini"

# ── 1. Take final screenshot before killing Stellarium ──────────────────────
sleep 2
take_screenshot /tmp/${TASK_NAME}_end_screenshot.png

# ── 2. Terminate Stellarium gracefully to flush config.ini ──────────────────
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

# ── 3. Parse config.ini ─────────────────────────────────────────────────────
CONFIG_JSON=$(python3 << 'PYEOF'
import configparser, json, os

config_path = "/home/ga/.stellarium/config.ini"
result = {
    "config_exists": False,
    "lat_rad": None, "lon_rad": None, "alt_m": None,
    "flag_atmosphere": None, "flag_azimuthal_grid": None,
    "flag_star_name": None, "flag_planets_hints": None,
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
        
        result["flag_atmosphere"] = get_bool('landscape', 'flag_atmosphere', 'false')
        result["flag_azimuthal_grid"] = get_bool('viewing', 'flag_azimuthal_grid', 'false')
        result["flag_star_name"] = get_bool('stars', 'flag_star_name', 'false')
        result["flag_planets_hints"] = get_bool('astro', 'flag_planets_hints', 'false')
    except Exception as e:
        result["config_error"] = str(e)

print(json.dumps(result))
PYEOF
)

# ── 4. Count new screenshots ────────────────────────────────────────────────
CURRENT_SS_COUNT=$(ls -1 "$SCREENSHOT_DIR" 2>/dev/null | wc -l)
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
echo "New screenshots: $FINAL_SS_COUNT"

# ── 5. Check Outreach Plan file ─────────────────────────────────────────────
PLAN_EXISTS="false"
PLAN_SIZE=0
KEYWORDS_FOUND="[]"

if [ -f "$PLAN_PATH" ]; then
    PLAN_EXISTS="true"
    PLAN_SIZE=$(wc -c < "$PLAN_PATH" 2>/dev/null || echo "0")
    
    KEYWORDS_FOUND=$(python3 << 'PYEOF'
import json, re
try:
    with open('/home/ga/Desktop/daytime_outreach_plan.txt', 'r', encoding='utf-8', errors='ignore') as f:
        content = f.read().lower()
        keywords = ["griffith", "june", "venus", "jupiter", "sirius"]
        found = [kw for kw in keywords if kw in content]
        print(json.dumps(found))
except:
    print("[]")
PYEOF
)
fi

echo "Plan file: exists=$PLAN_EXISTS, keywords=$KEYWORDS_FOUND"

# ── 6. Write result JSON ────────────────────────────────────────────────────
python3 << PYEOF
import json

config = json.loads('''$CONFIG_JSON''')
keywords_found = json.loads('''$KEYWORDS_FOUND''')

result = {
    "task_name": "$TASK_NAME",
    "task_start": $TASK_START,
    "config_exists": config.get("config_exists", False),
    "lat_rad": config.get("lat_rad"),
    "lon_rad": config.get("lon_rad"),
    "alt_m": config.get("alt_m"),
    "flag_atmosphere": config.get("flag_atmosphere"),
    "flag_azimuthal_grid": config.get("flag_azimuthal_grid"),
    "flag_star_name": config.get("flag_star_name"),
    "flag_planets_hints": config.get("flag_planets_hints"),
    "new_screenshot_count": $FINAL_SS_COUNT,
    "plan_exists": "$PLAN_EXISTS" == "true",
    "plan_size": $PLAN_SIZE,
    "keywords_found": keywords_found
}

with open("/tmp/${TASK_NAME}_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/${TASK_NAME}_result.json 2>/dev/null || sudo chmod 666 /tmp/${TASK_NAME}_result.json 2>/dev/null || true

echo "Export complete. Results saved to /tmp/${TASK_NAME}_result.json"
cat /tmp/${TASK_NAME}_result.json