#!/bin/bash
echo "=== Setting up sundial_analemma_reference task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Fallback screenshot function
if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

TASK_NAME="sundial_analemma_reference"

# ── 1. Kill any existing Stellarium instance ──────────────────────────────────
echo "--- Resetting Stellarium to known starting state ---"
pkill stellarium 2>/dev/null || true
sleep 3
pkill -9 stellarium 2>/dev/null || true
sleep 2

# ── 2. Write a fresh config with default display settings ─────────────────────
# Start state: atmosphere=ON, landscape=ON, azimuthal_grid=OFF, cardinal_points=OFF
# Agent must: turn landscape OFF, azimuthal ON, cardinal ON
cp /workspace/config/config.ini /home/ga/.stellarium/config.ini 2>/dev/null || true

python3 << 'PYEOF'
import configparser
import os

config_path = "/home/ga/.stellarium/config.ini"
if os.path.exists(config_path):
    cfg = configparser.RawConfigParser()
    cfg.read(config_path)

    # Ensure sections exist
    for section in ['landscape', 'viewing', 'stars', 'navigation', 'location_run_once']:
        if not cfg.has_section(section):
            cfg.add_section(section)

    # Set known starting state (default-like)
    cfg.set('landscape', 'flag_atmosphere', 'true')      # agent must keep ON
    cfg.set('landscape', 'flag_landscape', 'true')       # agent must turn OFF
    cfg.set('landscape', 'flag_fog', 'false')
    cfg.set('landscape', 'flag_cardinal_points', 'false') # agent must turn ON
    cfg.set('viewing', 'flag_equatorial_grid', 'false')
    cfg.set('viewing', 'flag_azimuthal_grid', 'false')   # agent must turn ON
    cfg.set('viewing', 'flag_constellation_drawing', 'false')
    cfg.set('viewing', 'flag_constellation_art', 'false')
    cfg.set('stars', 'flag_star_name', 'true')
    cfg.set('navigation', 'startup_time_mode', 'now')

    # Reset location to Pittsburgh default (agent must change to Jaipur)
    cfg.set('location_run_once', 'latitude', '0.705822')
    cfg.set('location_run_once', 'longitude', '-1.396192')
    cfg.set('location_run_once', 'altitude', '367')
    cfg.set('location_run_once', 'home_planet', 'Earth')
    cfg.set('location_run_once', 'landscape_name', 'guereins')

    with open(config_path, 'w') as f:
        cfg.write(f)
    print("Config reset to default starting state")
PYEOF

chown ga:ga /home/ga/.stellarium/config.ini

# ── 3. Remove any stale output files ──────────────────────────────────────────
rm -f /home/ga/Desktop/sundial_reference.txt 2>/dev/null || true

# ── 4. Record baseline screenshot count ───────────────────────────────────────
SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
mkdir -p "$SCREENSHOT_DIR"
chown -R ga:ga "$SCREENSHOT_DIR"
INITIAL_SCREENSHOT_COUNT=$(ls "$SCREENSHOT_DIR" 2>/dev/null | wc -l)
echo "$INITIAL_SCREENSHOT_COUNT" > /tmp/${TASK_NAME}_initial_screenshot_count
echo "Initial screenshot count: $INITIAL_SCREENSHOT_COUNT"

# ── 5. Copy observatory data to user-accessible location (just in case) ───────
mkdir -p /home/ga/data
cp /workspace/data/observatory_locations.json /home/ga/data/ 2>/dev/null || true
chown -R ga:ga /home/ga/data 2>/dev/null || true

# ── 6. Record task start timestamp ────────────────────────────────────────────
date +%s > /tmp/${TASK_NAME}_start_ts
echo "Task start timestamp recorded"

# ── 7. Start Stellarium ───────────────────────────────────────────────────────
echo "--- Starting Stellarium ---"
su - ga -c "bash /home/ga/start_stellarium.sh"

# Wait for Stellarium window to appear
ELAPSED=0
while [ $ELAPSED -lt 90 ]; do
    WID=$(DISPLAY=:1 xdotool search --name "Stellarium" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        echo "Stellarium window found (WID=$WID)"
        break
    fi
    sleep 3
    ELAPSED=$((ELAPSED + 3))
done

if [ $ELAPSED -ge 90 ]; then
    echo "WARNING: Stellarium window not detected within 90s"
fi

sleep 10

# ── 8. Dismiss any dialogs and maximize ───────────────────────────────────────
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

# ── 9. Take initial screenshot ────────────────────────────────────────────────
take_screenshot /tmp/${TASK_NAME}_start_screenshot.png

echo "=== Setup Complete ==="
echo "Starting state: atmosphere=ON, ground=ON, azimuthal_grid=OFF, location=Pittsburgh"
echo "Agent must: set location to Jantar Mantar (26.9246 N, 75.8235 E),"
echo "  set 4 dates (equinoxes/solstices 2023), disable ground, enable azimuthal grid,"
echo "  enable cardinal points, take 4 screenshots, and write sundial_reference.txt"