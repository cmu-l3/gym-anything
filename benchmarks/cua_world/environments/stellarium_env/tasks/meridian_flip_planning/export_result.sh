#!/bin/bash
echo "=== Exporting meridian_flip_planning result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

TASK_NAME="meridian_flip_planning"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")
INITIAL_SS_COUNT=$(cat /tmp/${TASK_NAME}_initial_screenshot_count 2>/dev/null || echo "0")
SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
NOTES_FILE="/home/ga/Desktop/meridian_flip_plan.txt"

# ── 1. Take final screenshot ──────────────────────────────────────────────────
sleep 2
take_screenshot /tmp/${TASK_NAME}_end_screenshot.png

# ── 2. Gracefully terminate to flush config ───────────────────────────────────
echo "--- Terminating Stellarium to flush config ---"
pkill -SIGTERM stellarium 2>/dev/null || true
for i in $(seq 1 15); do
    if ! pgrep stellarium > /dev/null 2>&1; then
        break
    fi
    sleep 1
done
pkill -9 stellarium 2>/dev/null || true
sleep 2

# ── 3. Evaluate Screenshots & Outputs ─────────────────────────────────────────
CURRENT_SS_COUNT=$(ls -1 "$SCREENSHOT_DIR" 2>/dev/null | wc -l)
NEW_SS_COUNT=$((CURRENT_SS_COUNT - INITIAL_SS_COUNT))

SS_NEW_BY_TIME=0
if [ -d "$SCREENSHOT_DIR" ]; then
    SS_NEW_BY_TIME=$(find "$SCREENSHOT_DIR" -newer /tmp/${TASK_NAME}_start_ts -type f 2>/dev/null | wc -l)
fi
FINAL_SS_COUNT=$(( SS_NEW_BY_TIME > NEW_SS_COUNT ? SS_NEW_BY_TIME : NEW_SS_COUNT ))

NOTES_EXISTS="false"
if [ -f "$NOTES_FILE" ]; then
    NOTES_EXISTS="true"
fi

# ── 4. Parse config.ini & file content into JSON ──────────────────────────────
python3 << PYEOF
import configparser, json, os

config_path = "/home/ga/.stellarium/config.ini"
notes_path = "$NOTES_FILE"

result = {
    "task_start": $TASK_START,
    "config_exists": False,
    "lat_rad": None,
    "lon_rad": None,
    "flag_atmosphere": None,
    "flag_landscape": None,
    "flag_equatorial_grid": None,
    "flag_meridian_line": None,
    "notes_exists": "$NOTES_EXISTS" == "true",
    "notes_content": "",
    "new_screenshot_count": $FINAL_SS_COUNT
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
        result["flag_equatorial_grid"] = get_bool('viewing', 'flag_equatorial_grid', 'false')
        result["flag_meridian_line"] = get_bool('viewing', 'flag_meridian_line', 'false')
        
    except Exception as e:
        pass

if result["notes_exists"]:
    try:
        with open(notes_path, 'r', encoding='utf-8') as f:
            result["notes_content"] = f.read()
    except:
        pass

temp_out = "/tmp/${TASK_NAME}_result.json"
with open(temp_out, "w") as f:
    json.dump(result, f)

os.chmod(temp_out, 0o666)
PYEOF

echo "=== Export Complete ==="