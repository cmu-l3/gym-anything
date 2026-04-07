#!/bin/bash
echo "=== Setting up coral_spawning_lunar_plan task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Fallback screenshot function
if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

TASK_NAME="coral_spawning_lunar_plan"

# ── 1. Kill any existing Stellarium instance and set a known starting config ──
echo "--- Resetting Stellarium to known starting state ---"
pkill stellarium 2>/dev/null || true
sleep 3
pkill -9 stellarium 2>/dev/null || true
sleep 2

# ── 2. Write a fresh config with default settings ────
# Start state: atmosphere=ON, landscape=guereins (default), azimuthal_grid=OFF
# Location = Paris. The agent must change location, landscape, and grid.
mkdir -p /home/ga/.stellarium
cp /workspace/config/config.ini /home/ga/.stellarium/config.ini 2>/dev/null || touch /home/ga/.stellarium/config.ini

python3 << 'PYEOF'
import configparser
import os

config_path = "/home/ga/.stellarium/config.ini"
cfg = configparser.RawConfigParser()
if os.path.exists(config_path):
    cfg.read(config_path)

# Ensure sections exist
for section in ['landscape', 'viewing', 'stars', 'navigation', 'location_run_once', 'init_location']:
    if not cfg.has_section(section):
        cfg.add_section(section)

# Set known starting state (default-like)
cfg.set('landscape', 'flag_atmosphere', 'true')
cfg.set('viewing', 'flag_azimuthal_grid', 'false')  # agent must turn ON

# Reset location to Paris (agent must change to Lizard Island)
cfg.set('location_run_once', 'latitude', '0.8526')
cfg.set('location_run_once', 'longitude', '0.0410')
cfg.set('location_run_once', 'altitude', '35')
cfg.set('location_run_once', 'home_planet', 'Earth')

# Set default landscape
cfg.set('location_run_once', 'landscape_name', 'guereins')
cfg.set('init_location', 'landscape_name', 'guereins')

with open(config_path, 'w') as f:
    cfg.write(f)

print("Config reset to default starting state")
PYEOF

chown -R ga:ga /home/ga/.stellarium

# ── 3. Remove any stale output files ────────
rm -f /home/ga/Desktop/dive_plan.txt 2>/dev/null || true

# ── 4. Remove stale screenshots to get accurate baseline count ────────────────
SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
mkdir -p "$SCREENSHOT_DIR"
chown -R ga:ga "$SCREENSHOT_DIR"
INITIAL_SCREENSHOT_COUNT=$(ls "$SCREENSHOT_DIR" 2>/dev/null | wc -l)
echo "$INITIAL_SCREENSHOT_COUNT" > /tmp/${TASK_NAME}_initial_screenshot_count
echo "Initial screenshot count: $INITIAL_SCREENSHOT_COUNT"

# ── 5. Record task start timestamp ───────────────────────────────────────────
date +%s > /tmp/${TASK_NAME}_start_ts
echo "Task start timestamp recorded"

# ── 6. Start Stellarium fresh ─────────────────────────────────────────────────
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

sleep 10

# ── 7. Dismiss any dialogs and maximize ──────────────────────────────────────
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

# ── 8. Take initial screenshot ───────────────────────────────────────────────
sleep 2
take_screenshot /tmp/${TASK_NAME}_start_screenshot.png

echo "=== Setup Complete ==="
echo "Starting state: location=Paris, landscape=guereins, azimuthal_grid=OFF"
echo "Agent must: set location to Lizard Island, change landscape to ocean, enable azimuthal grid,"
echo "capture 2 screenshots (Moon, Crux), and write dive_plan.txt"