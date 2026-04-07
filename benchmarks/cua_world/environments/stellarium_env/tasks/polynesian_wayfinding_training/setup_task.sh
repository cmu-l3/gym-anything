#!/bin/bash
echo "=== Setting up polynesian_wayfinding_training task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

TASK_NAME="polynesian_wayfinding_training"

# ── 1. Kill Stellarium and reset configuration to baseline state ──────────────
echo "--- Resetting Stellarium ---"
pkill stellarium 2>/dev/null || true
sleep 3
pkill -9 stellarium 2>/dev/null || true
sleep 2

# Write baseline config: agent must change location, sky culture, grids, and landscape
cp /workspace/config/config.ini /home/ga/.stellarium/config.ini

python3 << 'PYEOF'
import configparser

config_path = "/home/ga/.stellarium/config.ini"
cfg = configparser.RawConfigParser()
cfg.read(config_path)

for section in ['landscape', 'viewing', 'gui', 'navigation', 'location_run_once']:
    if not cfg.has_section(section):
        cfg.add_section(section)

# Default baseline state:
cfg.set('landscape', 'flag_atmosphere', 'true')
cfg.set('landscape', 'flag_landscape', 'true')     # Agent must turn OFF
cfg.set('viewing', 'flag_azimuthal_grid', 'false') # Agent must turn ON
cfg.set('viewing', 'flag_constellation_drawing', 'false') # Agent must turn ON
cfg.set('gui', 'sky_culture', 'western')           # Agent must change to hawaiian_starlines

# Reset location to default (e.g., Paris)
cfg.set('location_run_once', 'latitude', '0.852')
cfg.set('location_run_once', 'longitude', '0.041')
cfg.set('location_run_once', 'altitude', '35')

with open(config_path, 'w') as f:
    cfg.write(f)

print("Config set: default Western sky culture, ground ON, grids OFF (agent must configure)")
PYEOF

chown ga:ga /home/ga/.stellarium/config.ini

# ── 2. Clean up previous artifacts to ensure accurate scoring ────────────────
rm -f /home/ga/Desktop/wayfinding_guide.txt 2>/dev/null || true

SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
mkdir -p "$SCREENSHOT_DIR"
chown -R ga:ga "$SCREENSHOT_DIR"
INITIAL_SS_COUNT=$(ls -1 "$SCREENSHOT_DIR" 2>/dev/null | wc -l)
echo "$INITIAL_SS_COUNT" > /tmp/${TASK_NAME}_initial_screenshot_count

# ── 3. Record task start timestamp ───────────────────────────────────────────
date +%s > /tmp/${TASK_NAME}_start_ts

# ── 4. Start Stellarium ──────────────────────────────────────────────────────
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

# Dismiss startup popups and maximize
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

# ── 5. Take initial screenshot ───────────────────────────────────────────────
take_screenshot /tmp/${TASK_NAME}_start_screenshot.png

echo "=== Setup Complete ==="