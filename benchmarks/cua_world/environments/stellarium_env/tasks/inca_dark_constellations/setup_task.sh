#!/bin/bash
echo "=== Setting up inca_dark_constellations task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Fallback screenshot function
if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

TASK_NAME="inca_dark_constellations"

# ── 1. Kill existing Stellarium and reset config to default ─────────────────
echo "--- Resetting Stellarium config ---"
pkill stellarium 2>/dev/null || true
sleep 3
pkill -9 stellarium 2>/dev/null || true
sleep 2

mkdir -p /home/ga/.stellarium
cp /workspace/config/config.ini /home/ga/.stellarium/config.ini 2>/dev/null || true

python3 << 'PYEOF'
import configparser
import os

config_path = "/home/ga/.stellarium/config.ini"
cfg = configparser.RawConfigParser()
if os.path.exists(config_path):
    cfg.read(config_path)

for section in ['landscape', 'viewing', 'stars', 'navigation', 'location_run_once', 'localization', 'astro']:
    if not cfg.has_section(section):
        cfg.add_section(section)

# Default starting state: modern date, Western culture, Pittsburgh, default Milky Way
cfg.set('landscape', 'flag_atmosphere', 'true')     # Agent must turn OFF
cfg.set('landscape', 'flag_landscape', 'true')      # Agent must turn OFF
cfg.set('viewing', 'flag_constellation_art', 'false')       # Agent must turn ON
cfg.set('viewing', 'flag_constellation_drawing', 'false')   # Agent must turn ON
cfg.set('localization', 'sky_culture', 'western')           # Agent must set to 'inca'
cfg.set('astro', 'milky_way_intensity', '1.0')              # Agent must set >= 4.0
cfg.set('navigation', 'startup_time_mode', 'actual')

# Set location to Pittsburgh
cfg.set('location_run_once', 'latitude', '0.705822')
cfg.set('location_run_once', 'longitude', '-1.396192')
cfg.set('location_run_once', 'altitude', '367')

with open(config_path, 'w') as f:
    cfg.write(f)

print("Config set to default (Western culture, modern date, defaults)")
PYEOF

chown ga:ga /home/ga/.stellarium/config.ini

# ── 2. Remove stale files to prevent anti-gaming ───────────────────────────
rm -f /home/ga/Desktop/inca_lecture_notes.txt 2>/dev/null || true

# ── 3. Record baseline screenshot count ──────────────────────────────────────
SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
mkdir -p "$SCREENSHOT_DIR"
chown -R ga:ga "$SCREENSHOT_DIR"
INITIAL_SS_COUNT=$(ls "$SCREENSHOT_DIR" 2>/dev/null | wc -l)
echo "$INITIAL_SS_COUNT" > /tmp/${TASK_NAME}_initial_screenshot_count
echo "Initial screenshot count: $INITIAL_SS_COUNT"

# ── 4. Record task start timestamp ───────────────────────────────────────────
date +%s > /tmp/${TASK_NAME}_start_ts

# ── 5. Start Stellarium ───────────────────────────────────────────────────────
echo "--- Starting Stellarium ---"
su - ga -c "bash /home/ga/start_stellarium.sh"

ELAPSED=0
while [ $ELAPSED -lt 90 ]; do
    WID=$(DISPLAY=:1 xdotool search --name "Stellarium" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        echo "Stellarium window found"
        break
    fi
    sleep 3
    ELAPSED=$((ELAPSED + 3))
done

sleep 10

# Dismiss dialogs
for i in 1 2; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
done

DISPLAY=:1 wmctrl -r "Stellarium" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

WID=$(DISPLAY=:1 xdotool search --name "Stellarium" 2>/dev/null | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 xdotool windowactivate "$WID" 2>/dev/null || true
    DISPLAY=:1 xdotool windowfocus "$WID" 2>/dev/null || true
fi
sleep 2

# ── 6. Take initial screenshot ────────────────────────────────────────────────
take_screenshot /tmp/${TASK_NAME}_start_screenshot.png

echo "=== Setup Complete ==="