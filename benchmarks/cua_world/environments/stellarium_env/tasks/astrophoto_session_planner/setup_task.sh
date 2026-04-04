#!/bin/bash
echo "=== Setting up astrophoto_session_planner task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Fallback screenshot function
if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

# ── 1. Kill any existing Stellarium instance and set a known starting config ──
echo "--- Resetting Stellarium to known starting state ---"
pkill stellarium 2>/dev/null || true
sleep 3
pkill -9 stellarium 2>/dev/null || true
sleep 2

# ── 2. Write a fresh config with default (non-configured) display settings ────
# Start state: atmosphere=ON, landscape=ON, equatorial_grid=OFF, azimuthal_grid=OFF
# Agent must: turn atmosphere OFF, landscape OFF, equatorial_grid ON
cp /workspace/config/config.ini /home/ga/.stellarium/config.ini

python3 << 'PYEOF'
import configparser

config_path = "/home/ga/.stellarium/config.ini"
cfg = configparser.RawConfigParser()
cfg.read(config_path)

# Ensure sections exist
for section in ['landscape', 'viewing', 'stars', 'navigation', 'location_run_once']:
    if not cfg.has_section(section):
        cfg.add_section(section)

# Set known starting state (default-like: everything ON/OFF as defaults)
cfg.set('landscape', 'flag_atmosphere', 'true')   # agent must turn OFF
cfg.set('landscape', 'flag_landscape', 'true')    # agent must turn OFF
cfg.set('landscape', 'flag_fog', 'false')
cfg.set('viewing', 'flag_equatorial_grid', 'false')  # agent must turn ON
cfg.set('viewing', 'flag_azimuthal_grid', 'false')
cfg.set('viewing', 'flag_constellation_drawing', 'false')
cfg.set('viewing', 'flag_constellation_art', 'false')
cfg.set('stars', 'flag_star_name', 'true')
cfg.set('navigation', 'startup_time_mode', 'now')
cfg.set('navigation', 'preset_sky_time', '2451545.0')

# Reset location to Pittsburgh default (agent must change to Paranal)
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

# ── 3. Remove any stale output files so do-nothing test gives score=0 ────────
rm -f /home/ga/Desktop/session_notes.txt 2>/dev/null || true

# ── 4. Remove stale screenshots to get accurate baseline count ────────────────
# Don't delete all screenshots — just record the count before task
SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
mkdir -p "$SCREENSHOT_DIR"
chown -R ga:ga "$SCREENSHOT_DIR"
INITIAL_SCREENSHOT_COUNT=$(ls "$SCREENSHOT_DIR" 2>/dev/null | wc -l)
echo "$INITIAL_SCREENSHOT_COUNT" > /tmp/astrophoto_session_planner_initial_screenshot_count
echo "Initial screenshot count: $INITIAL_SCREENSHOT_COUNT"

# ── 5. Copy observatory data to user-accessible location ─────────────────────
cp /workspace/data/observatory_locations.json /home/ga/data/ 2>/dev/null || true
cp /workspace/data/messier_catalog.json /home/ga/data/ 2>/dev/null || true
chown -R ga:ga /home/ga/data 2>/dev/null || true

# ── 6. Record task start timestamp ───────────────────────────────────────────
date +%s > /tmp/astrophoto_session_planner_start_ts
echo "Task start timestamp recorded"

# ── 7. Start Stellarium fresh ─────────────────────────────────────────────────
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

# ── 8. Dismiss any dialogs and maximize ──────────────────────────────────────
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

# ── 9. Take initial screenshot ───────────────────────────────────────────────
sleep 2
take_screenshot /tmp/astrophoto_session_planner_start_screenshot.png

echo "=== Setup Complete ==="
echo "Starting state: atmosphere=ON, ground=ON, equatorial_grid=OFF, location=Pittsburgh"
echo "Agent must: set location to Paranal Observatory (from observatory_locations.json),"
echo "  set date to July 16 2023 01:00 UTC, disable atmosphere, disable ground,"
echo "  enable equatorial grid, search and screenshot 3 NGC targets, write session_notes.txt"
