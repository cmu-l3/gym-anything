#!/bin/bash
echo "=== Exporting galilean_moons_exhibit result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

TASK_NAME="galilean_moons_exhibit"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")
INITIAL_SS_COUNT=$(cat /tmp/${TASK_NAME}_initial_screenshot_count 2>/dev/null || echo "0")
SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
NOTES_FILE="/home/ga/Desktop/galileo_exhibit.txt"

# ── 1. Take final screenshot before killing Stellarium ────────────────────────
take_screenshot /tmp/${TASK_NAME}_end_screenshot.png

# ── 2. Gracefully terminate Stellarium to flush config.ini ───────────────────
pkill -SIGTERM stellarium 2>/dev/null || true
for i in $(seq 1 15); do
    if ! pgrep stellarium > /dev/null 2>&1; then
        break
    fi
    sleep 1
done
pkill -9 stellarium 2>/dev/null || true
sleep 2

# ── 3. Parse config.ini and create output JSON via Python ────────────────────
# We write the results using Python to safely handle JSON encoding of notes content
python3 << PYEOF
import configparser
import json
import os

config_path = "/home/ga/.stellarium/config.ini"
config_state = {
    "config_exists": False,
    "lat_rad": None, 
    "lon_rad": None,
    "flag_atmosphere": None, 
    "flag_landscape": None,
    "config_error": None
}

if os.path.exists(config_path):
    config_state["config_exists"] = True
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

        # CRITICAL TEST: Check 'init_location' explicitly.
        # This confirms they actually pressed "Save settings" as instructed.
        config_state["lat_rad"] = get_float('init_location', 'latitude', -999)
        config_state["lon_rad"] = get_float('init_location', 'longitude', -999)
            
        config_state["flag_atmosphere"] = get_bool('landscape', 'flag_atmosphere', 'true')
        config_state["flag_landscape"] = get_bool('landscape', 'flag_landscape', 'true')
    except Exception as e:
        config_state["config_error"] = str(e)

# ── 4. Count new screenshots ──────────────────────────────────────────────────
current_ss_count = 0
try:
    current_ss_count = len(os.listdir("$SCREENSHOT_DIR"))
except FileNotFoundError:
    pass

new_ss_count = max(0, current_ss_count - $INITIAL_SS_COUNT)

# Fallback: Count files strictly modified after task start
ss_new_by_time = 0
if os.path.exists("$SCREENSHOT_DIR"):
    for file in os.listdir("$SCREENSHOT_DIR"):
        path = os.path.join("$SCREENSHOT_DIR", file)
        if os.path.isfile(path) and os.path.getmtime(path) > $TASK_START:
            ss_new_by_time += 1

final_ss_count = max(new_ss_count, ss_new_by_time)

# ── 5. Check Notes File ───────────────────────────────────────────────────────
notes_exists = False
notes_content = ""
notes_path = "$NOTES_FILE"

if os.path.exists(notes_path) and os.path.getmtime(notes_path) > $TASK_START:
    notes_exists = True
    with open(notes_path, 'r', errors='ignore') as f:
        notes_content = f.read(2000)

result = {
    "task_start": $TASK_START,
    "config": config_state,
    "new_screenshot_count": final_ss_count,
    "notes_exists": notes_exists,
    "notes_content": notes_content
}

with open("/tmp/${TASK_NAME}_result.json", "w") as f:
    json.dump(result, f)
PYEOF

chmod 666 /tmp/${TASK_NAME}_result.json 2>/dev/null || true
echo "Result JSON written."