#!/bin/bash
echo "=== Exporting architect_solar_study result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

TASK_NAME="architect_solar_study"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")
INITIAL_SS_COUNT=$(cat /tmp/${TASK_NAME}_initial_screenshot_count 2>/dev/null || echo "0")
SCREENSHOT_DIR="/home/ga/Pictures/stellarium"

# ── 1. Take final screenshot before killing Stellarium ────────────────────────
sleep 2
take_screenshot /tmp/${TASK_NAME}_end_screenshot.png

# ── 2. Gracefully terminate Stellarium to flush config.ini ───────────────────
echo "--- Terminating Stellarium to flush config ---"
pkill -SIGTERM stellarium 2>/dev/null || true

for i in $(seq 1 15); do
    if ! pgrep stellarium > /dev/null 2>&1; then
        echo "Stellarium exited gracefully"
        break
    fi
    sleep 1
done

pkill -9 stellarium 2>/dev/null || true
sleep 2

# ── 3. Count new screenshots ──────────────────────────────────────────────────
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

# ── 4. Parse config and write result JSON ─────────────────────────────────────
python3 << PYEOF
import configparser, json, os

config_path = "/home/ga/.stellarium/config.ini"
config = {}

if os.path.exists(config_path):
    try:
        cfg = configparser.RawConfigParser()
        cfg.read(config_path)

        def get_bool(key, default=None):
            for section in cfg.sections():
                if cfg.has_option(section, key):
                    try: return cfg.get(section, key).lower().strip() == 'true'
                    except: pass
            return default

        def get_float_loc(key):
            if cfg.has_option('location_run_once', key):
                try: return float(cfg.get('location_run_once', key))
                except: pass
            if cfg.has_option('init_location', key):
                try: return float(cfg.get('init_location', key))
                except: pass
            return None

        config["lat_rad"] = get_float_loc("latitude")
        config["lon_rad"] = get_float_loc("longitude")
        config["flag_atmosphere"] = get_bool("flag_atmosphere")
        config["flag_landscape"] = get_bool("flag_landscape")
        config["flag_azimuthal_grid"] = get_bool("flag_azimuthal_grid")
        config["flag_cardinal_points"] = get_bool("flag_cardinal_points")
    except Exception as e:
        print(f"Error parsing config: {e}")

report_path = "/home/ga/Desktop/solar_study_report.txt"
report_content = ""
report_exists = os.path.exists(report_path)
report_size = 0
if report_exists:
    report_size = os.path.getsize(report_path)
    try:
        with open(report_path, 'r', encoding='utf-8', errors='ignore') as f:
            # truncate to 2000 chars to avoid huge JSONs if the agent went crazy
            report_content = f.read()[:2000]
    except Exception:
        pass

result = {
    "task_start": $TASK_START,
    "lat_rad": config.get("lat_rad"),
    "lon_rad": config.get("lon_rad"),
    "flag_atmosphere": config.get("flag_atmosphere"),
    "flag_landscape": config.get("flag_landscape"),
    "flag_azimuthal_grid": config.get("flag_azimuthal_grid"),
    "flag_cardinal_points": config.get("flag_cardinal_points"),
    "new_screenshot_count": $FINAL_SS_COUNT,
    "report_exists": report_exists,
    "report_size": report_size,
    "report_content": report_content
}

with open('/tmp/${TASK_NAME}_result.json', 'w') as f:
    json.dump(result, f)
PYEOF

echo "Result JSON written."
cat /tmp/${TASK_NAME}_result.json