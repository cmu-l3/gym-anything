#!/bin/bash
echo "=== Setting up polar_night_lighting_ref task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Fallback screenshot function if task_utils doesn't provide it
if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

TASK_NAME="polar_night_lighting_ref"

# ── 1. Terminate any running Stellarium instance ──────────────────────────────
echo "--- Resetting Stellarium ---"
pkill stellarium 2>/dev/null || true
sleep 3
pkill -9 stellarium 2>/dev/null || true
sleep 2

# ── 2. Write a default starting config ────────────────────────────────────────
# Default: Guereins (lat ~46N), atmosphere ON, landscape ON, all grids/lines OFF
cp /workspace/config/config.ini /home/ga/.stellarium/config.ini

python3 << 'PYEOF'
import configparser
import os

config_path = "/home/ga/.stellarium/config.ini"
cfg = configparser.RawConfigParser()
cfg.read(config_path)

for section in ['landscape', 'viewing', 'stars', 'navigation', 'location_run_once']:
    if not cfg.has_section(section):
        cfg.add_section(section)

# Set starting state
cfg.set('landscape', 'flag_atmosphere', 'true')     # Agent keeps ON
cfg.set('landscape', 'flag_landscape', 'true')      # Agent turns OFF
cfg.set('landscape', 'flag_cardinal_points', 'false') # Agent turns ON
cfg.set('viewing', 'flag_constellation_drawing', 'false') # Agent turns ON
cfg.set('viewing', 'flag_constellation_name', 'false')    # Agent turns ON
cfg.set('viewing', 'flag_azimuthal_grid', 'false')        # Agent turns ON
cfg.set('viewing', 'flag_equatorial_grid', 'false')
cfg.set('viewing', 'flag_constellation_art', 'false')
cfg.set('stars', 'flag_star_name', 'true')
cfg.set('navigation', 'startup_time_mode', 'now')

# Reset location to standard Guereins default
cfg.set('location_run_once', 'latitude', '0.80397')
cfg.set('location_run_once', 'longitude', '0.0834')
cfg.set('location_run_once', 'altitude', '200')
cfg.set('location_run_once', 'home_planet', 'Earth')
cfg.set('location_run_once', 'landscape_name', 'guereins')

with open(config_path, 'w') as f:
    cfg.write(f)

print("Config reset to default (Guereins, no grids/labels)")
PYEOF

chown ga:ga /home/ga/.stellarium/config.ini

# ── 3. Remove any stale output files ──────────────────────────────────────────
rm -f /home/ga/Desktop/polar_night_lighting_notes.txt 2>/dev/null || true

# ── 4. Setup directories and record baseline screenshots ──────────────────────
SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
mkdir -p "$SCREENSHOT_DIR"
chown -R ga:ga "$SCREENSHOT_DIR"
INITIAL_SS_COUNT=$(ls -1 "$SCREENSHOT_DIR" 2>/dev/null | wc -l)
echo "$INITIAL_SS_COUNT" > /tmp/${TASK_NAME}_initial_screenshot_count
echo "Initial screenshot count: $INITIAL_SS_COUNT"

# ── 5. Record task start timestamp (Anti-gaming) ──────────────────────────────
date +%s > /tmp/${TASK_NAME}_start_ts

# ── 6. Start Stellarium ───────────────────────────────────────────────────────
echo "--- Starting Stellarium ---"
su - ga -c "bash /home/ga/start_stellarium.sh"

# Wait for Stellarium to render
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

# ── 7. Dismiss popups and maximize ────────────────────────────────────────────
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

# ── 8. Take initial screenshot ────────────────────────────────────────────────
take_screenshot /tmp/${TASK_NAME}_start_screenshot.png

echo "=== Setup Complete ==="
echo "Agent should start in default view. Must reconfigure for Tromsø polar night."