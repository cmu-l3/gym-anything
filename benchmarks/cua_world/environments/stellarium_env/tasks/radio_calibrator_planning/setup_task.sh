#!/bin/bash
echo "=== Setting up radio_calibrator_planning task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Fallback screenshot function if utilities are missing
if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

TASK_NAME="radio_calibrator_planning"

# ── 1. Kill any existing Stellarium instance and set a known starting config ──
echo "--- Resetting Stellarium to known starting state ---"
pkill stellarium 2>/dev/null || true
sleep 3
pkill -9 stellarium 2>/dev/null || true
sleep 2

# ── 2. Write a fresh config with default (non-configured) display settings ────
# Start state: atmosphere=ON, landscape=ON, equatorial_grid=OFF
# Agent must: turn atmosphere OFF, landscape OFF, equatorial_grid ON
mkdir -p /home/ga/.stellarium
cp /workspace/config/config.ini /home/ga/.stellarium/config.ini 2>/dev/null || true

python3 << 'PYEOF'
import configparser
import os

config_path = "/home/ga/.stellarium/config.ini"
if not os.path.exists(config_path):
    with open(config_path, 'w') as f:
        f.write("")

cfg = configparser.RawConfigParser()
cfg.read(config_path)

# Ensure sections exist
for section in ['landscape', 'viewing', 'stars', 'navigation', 'location_run_once']:
    if not cfg.has_section(section):
        cfg.add_section(section)

# Set incorrect starting state (defaults)
cfg.set('landscape', 'flag_atmosphere', 'true')      # agent must turn OFF
cfg.set('landscape', 'flag_landscape', 'true')       # agent must turn OFF
cfg.set('landscape', 'flag_fog', 'false')
cfg.set('viewing', 'flag_equatorial_grid', 'false')  # agent must turn ON
cfg.set('viewing', 'flag_azimuthal_grid', 'false')
cfg.set('navigation', 'startup_time_mode', 'now')
cfg.set('navigation', 'preset_sky_time', '2451545.0')

# Reset location to Paris default (agent must change to Green Bank)
cfg.set('location_run_once', 'latitude', '0.8521')
cfg.set('location_run_once', 'longitude', '0.0408')
cfg.set('location_run_once', 'altitude', '35')
cfg.set('location_run_once', 'home_planet', 'Earth')

with open(config_path, 'w') as f:
    cfg.write(f)

print("Config reset to default starting state (Paris, Atmosphere ON, Ground ON, Grid OFF)")
PYEOF

chown ga:ga /home/ga/.stellarium/config.ini

# ── 3. Clean up any previous task artifacts ──────────────────────────────────
rm -f /home/ga/Desktop/calibration_plan.txt 2>/dev/null || true

SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
mkdir -p "$SCREENSHOT_DIR"
chown -R ga:ga "$SCREENSHOT_DIR"

INITIAL_SCREENSHOT_COUNT=$(ls "$SCREENSHOT_DIR" 2>/dev/null | wc -l)
echo "$INITIAL_SCREENSHOT_COUNT" > /tmp/${TASK_NAME}_initial_screenshot_count
echo "Initial screenshot count: $INITIAL_SCREENSHOT_COUNT"

# ── 4. Copy real observatory data to user-accessible location ────────────────
mkdir -p /home/ga/data
cp /workspace/data/observatory_locations.json /home/ga/data/ 2>/dev/null || true
chown -R ga:ga /home/ga/data 2>/dev/null || true

# ── 5. Record task start timestamp (Anti-gaming measure) ─────────────────────
date +%s > /tmp/${TASK_NAME}_start_ts
echo "Task start timestamp recorded"

# ── 6. Start Stellarium ──────────────────────────────────────────────────────
echo "--- Starting Stellarium ---"
su - ga -c "bash /home/ga/start_stellarium.sh" > /dev/null 2>&1 &

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

sleep 10

# ── 7. Dismiss any dialogs and maximize ──────────────────────────────────────
for i in 1 2 3; do
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

# ── 8. Take initial screenshot ───────────────────────────────────────────────
take_screenshot /tmp/${TASK_NAME}_start_screenshot.png

echo "=== Setup Complete ==="
echo "Agent must: set location to Green Bank Observatory, time to Jan 20 2024 05:00 UTC,"
echo "disable atmosphere & ground, enable equatorial grid, find M1/M42/M87,"
echo "take 3 screenshots, and write the calibration plan to the Desktop."