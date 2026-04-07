#!/bin/bash
echo "=== Setting up hilal_crescent_assessment task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Fallback screenshot function if not provided by task_utils
if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

TASK_NAME="hilal_crescent_assessment"

# ── 1. Kill any existing Stellarium instance to set a known starting config ──
echo "--- Resetting Stellarium to known starting state ---"
pkill stellarium 2>/dev/null || true
sleep 3
pkill -9 stellarium 2>/dev/null || true
sleep 2

# ── 2. Write a fresh config with opposing display settings ────
# Start state: atmosphere=OFF, landscape=ON, azimuthal_grid=OFF
# Agent must: turn atmosphere ON, landscape OFF, azimuthal_grid ON
mkdir -p /home/ga/.stellarium
cp /workspace/config/config.ini /home/ga/.stellarium/config.ini 2>/dev/null || true

python3 << 'PYEOF'
import configparser

config_path = "/home/ga/.stellarium/config.ini"
cfg = configparser.RawConfigParser()
cfg.read(config_path)

# Ensure sections exist
for section in ['landscape', 'viewing', 'stars', 'navigation', 'location_run_once']:
    if not cfg.has_section(section):
        cfg.add_section(section)

# Set starting state (opposite of what agent needs to achieve)
cfg.set('landscape', 'flag_atmosphere', 'false')  # agent must turn ON
cfg.set('landscape', 'flag_landscape', 'true')    # agent must turn OFF
cfg.set('landscape', 'flag_fog', 'false')
cfg.set('viewing', 'flag_azimuthal_grid', 'false') # agent must turn ON
cfg.set('viewing', 'flag_equatorial_grid', 'false')
cfg.set('stars', 'flag_star_name', 'true')
cfg.set('navigation', 'startup_time_mode', 'now')
cfg.set('navigation', 'preset_sky_time', '2451545.0') # Default J2000

# Reset location to Paris default (agent must change to Mecca)
cfg.set('location_run_once', 'latitude', '0.8523')
cfg.set('location_run_once', 'longitude', '0.0408')
cfg.set('location_run_once', 'altitude', '35')
cfg.set('location_run_once', 'home_planet', 'Earth')
cfg.set('location_run_once', 'landscape_name', 'guereins')

with open(config_path, 'w') as f:
    cfg.write(f)

print("Config reset to default starting state")
PYEOF

chown ga:ga /home/ga/.stellarium/config.ini

# ── 3. Clean up stale output files to ensure zero score on "do nothing" ──
rm -f /home/ga/Desktop/hilal_report.txt 2>/dev/null || true

# ── 4. Record baseline screenshot count ──
SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
mkdir -p "$SCREENSHOT_DIR"
chown -R ga:ga "$SCREENSHOT_DIR"
INITIAL_SCREENSHOT_COUNT=$(ls -1 "$SCREENSHOT_DIR" 2>/dev/null | wc -l)
echo "$INITIAL_SCREENSHOT_COUNT" > /tmp/${TASK_NAME}_initial_screenshot_count
echo "Initial screenshot count: $INITIAL_SCREENSHOT_COUNT"

# ── 5. Record task start timestamp ──
date +%s > /tmp/${TASK_NAME}_start_ts
echo "Task start timestamp recorded"

# ── 6. Start Stellarium ──
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

# ── 7. Dismiss dialogs and maximize ──
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

# ── 8. Take initial screenshot ──
take_screenshot /tmp/${TASK_NAME}_start_screenshot.png

echo "=== Setup Complete ==="
echo "Starting state: Atmosphere=OFF, Landscape=ON, Azimuthal=OFF, Location=Paris"
echo "Agent must: Location=Mecca (21.42N, 39.83E), Time=Mar 22 2023 15:45 UTC,"
echo "Atmosphere=ON, Landscape=OFF, Azimuthal=ON, 3+ screenshots, write hilal_report.txt."