#!/bin/bash
echo "=== Setting up eclipse_contact_time_analysis task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Fallback screenshot function
if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

TASK_NAME="eclipse_contact_time_analysis"

# ── 1. Kill Stellarium and set a known starting state ─────────────────────────
echo "--- Resetting Stellarium to known starting state ---"
pkill stellarium 2>/dev/null || true
sleep 3
pkill -9 stellarium 2>/dev/null || true
sleep 2

# ── 2. Write a starting config that is deliberately WRONG for the task ────────
# Start: atmosphere OFF (agent must turn ON), landscape ON (agent must turn OFF),
# constellations OFF (agent must turn ON), location = Pittsburgh (default)
mkdir -p /home/ga/.stellarium
cp /workspace/config/config.ini /home/ga/.stellarium/config.ini 2>/dev/null || true

python3 << 'PYEOF'
import configparser

config_path = "/home/ga/.stellarium/config.ini"
cfg = configparser.RawConfigParser()
cfg.read(config_path)

for section in ['landscape', 'viewing', 'stars', 'navigation', 'location_run_once']:
    if not cfg.has_section(section):
        cfg.add_section(section)

# Starting state — deliberately wrong for the task
cfg.set('landscape', 'flag_atmosphere', 'false')            # Agent must turn ON
cfg.set('landscape', 'flag_landscape', 'true')              # Agent must turn OFF
cfg.set('landscape', 'flag_fog', 'false')
cfg.set('viewing', 'flag_constellation_drawing', 'false')   # Agent must turn ON
cfg.set('viewing', 'flag_constellation_name', 'false')
cfg.set('viewing', 'flag_constellation_art', 'false')
cfg.set('viewing', 'flag_azimuthal_grid', 'false')
cfg.set('viewing', 'flag_equatorial_grid', 'false')
cfg.set('stars', 'flag_star_name', 'true')
cfg.set('navigation', 'startup_time_mode', 'now')
cfg.set('navigation', 'preset_sky_time', '2451545.0')

# Default location: Pittsburgh (agent must change to Reykjavik, then Rome)
cfg.set('location_run_once', 'latitude', '0.705822')
cfg.set('location_run_once', 'longitude', '-1.396192')
cfg.set('location_run_once', 'altitude', '367')
cfg.set('location_run_once', 'home_planet', 'Earth')
cfg.set('location_run_once', 'landscape_name', 'guereins')

with open(config_path, 'w') as f:
    cfg.write(f)

print("Config reset to wrong starting state (Pittsburgh, atmosphere OFF, landscape ON, constellations OFF)")
PYEOF

chown -R ga:ga /home/ga/.stellarium

# ── 3. Remove stale output files BEFORE recording timestamp ───────────────────
rm -f /home/ga/Desktop/eclipse_contact_times.txt 2>/dev/null || true

# ── 4. Record baseline screenshot count ───────────────────────────────────────
SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
mkdir -p "$SCREENSHOT_DIR"
chown -R ga:ga "$SCREENSHOT_DIR"
INITIAL_SS_COUNT=$(ls -1 "$SCREENSHOT_DIR" 2>/dev/null | wc -l)
echo "$INITIAL_SS_COUNT" > /tmp/${TASK_NAME}_initial_screenshot_count
echo "Initial screenshot count: $INITIAL_SS_COUNT"

# ── 5. Record task start timestamp ────────────────────────────────────────────
date +%s > /tmp/${TASK_NAME}_start_ts
echo "Task start timestamp recorded"

# ── 6. Copy data files to user-accessible location ───────────────────────────
mkdir -p /home/ga/data
cp /workspace/data/historical_eclipses.json /home/ga/data/ 2>/dev/null || true
cp /workspace/data/observatory_locations.json /home/ga/data/ 2>/dev/null || true
cp /workspace/data/messier_catalog.json /home/ga/data/ 2>/dev/null || true
chown -R ga:ga /home/ga/data 2>/dev/null || true

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
echo "Starting state: Pittsburgh, atmosphere OFF, landscape ON, constellations OFF"
echo "Agent must: read eclipse data from /home/ga/data/historical_eclipses.json,"
echo "  set location to Reykjavik Iceland, set date to Aug 12 2026,"
echo "  enable atmosphere, disable landscape, enable constellation lines,"
echo "  find all four eclipse contact times (C1-C4) by advancing time,"
echo "  observe totality, check Rome as control, write report."
