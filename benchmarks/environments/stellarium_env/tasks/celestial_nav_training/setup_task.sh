#!/bin/bash
echo "=== Setting up celestial_nav_training task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

TASK_NAME="celestial_nav_training"

# ── 1. Kill Stellarium and set intentionally misconfigured starting state ─────
echo "--- Setting up intentionally misconfigured starting state ---"
pkill stellarium 2>/dev/null || true
sleep 3
pkill -9 stellarium 2>/dev/null || true
sleep 2

# ── 2. Write starting config with intentional misconfigurations ───────────────
# Starting state: atmosphere=ON, landscape=ON, constellation_drawing=ON,
#   constellation_art=ON, azimuthal_grid=OFF, star_name=OFF
# Agent must: turn atmosphere OFF, turn azimuthal_grid ON, turn star_name ON,
#   turn constellation_drawing OFF, turn constellation_art OFF ─────────────────
cp /workspace/config/config.ini /home/ga/.stellarium/config.ini

python3 << 'PYEOF'
import configparser

config_path = "/home/ga/.stellarium/config.ini"
cfg = configparser.RawConfigParser()
cfg.read(config_path)

for section in ['landscape', 'viewing', 'stars', 'navigation', 'location_run_once']:
    if not cfg.has_section(section):
        cfg.add_section(section)

# Intentionally WRONG starting state — agent must fix everything
cfg.set('landscape', 'flag_atmosphere', 'true')    # must turn OFF
cfg.set('landscape', 'flag_landscape', 'true')     # acceptable to keep or turn off
cfg.set('landscape', 'flag_fog', 'false')
cfg.set('landscape', 'flag_cardinal_points', 'false')
cfg.set('viewing', 'flag_constellation_drawing', 'true')  # must turn OFF
cfg.set('viewing', 'flag_constellation_art', 'true')      # must turn OFF
cfg.set('viewing', 'flag_azimuthal_grid', 'false')        # must turn ON
cfg.set('viewing', 'flag_equatorial_grid', 'false')
cfg.set('stars', 'flag_star_name', 'false')               # must turn ON

# Reset navigation to now (default)
cfg.set('navigation', 'startup_time_mode', 'now')
cfg.set('navigation', 'preset_sky_time', '2451545.0')

# Reset location to Pittsburgh default
cfg.set('location_run_once', 'latitude', '0.705822')
cfg.set('location_run_once', 'longitude', '-1.396192')
cfg.set('location_run_once', 'altitude', '367')
cfg.set('location_run_once', 'home_planet', 'Earth')
cfg.set('location_run_once', 'landscape_name', 'guereins')

with open(config_path, 'w') as f:
    cfg.write(f)

print("INTENTIONALLY WRONG starting state set:")
print("  atmosphere=ON (must turn OFF)")
print("  constellation_drawing=ON (must turn OFF)")
print("  constellation_art=ON (must turn OFF)")
print("  azimuthal_grid=OFF (must turn ON)")
print("  star_name=OFF (must turn ON)")
PYEOF

chown ga:ga /home/ga/.stellarium/config.ini

# ── 3. Remove stale output files ──────────────────────────────────────────────
rm -f /home/ga/Desktop/nav_log.txt 2>/dev/null || true

# ── 4. Record baseline screenshot count ──────────────────────────────────────
SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
mkdir -p "$SCREENSHOT_DIR"
chown -R ga:ga "$SCREENSHOT_DIR"
INITIAL_SS_COUNT=$(ls "$SCREENSHOT_DIR" 2>/dev/null | wc -l)
echo "$INITIAL_SS_COUNT" > /tmp/${TASK_NAME}_initial_screenshot_count
echo "Initial screenshot count: $INITIAL_SS_COUNT"

# ── 5. Copy data files ────────────────────────────────────────────────────────
mkdir -p /home/ga/data
cp /workspace/data/observatory_locations.json /home/ga/data/ 2>/dev/null || true
chown -R ga:ga /home/ga/data 2>/dev/null || true

# ── 6. Record task start timestamp ───────────────────────────────────────────
date +%s > /tmp/${TASK_NAME}_start_ts

# ── 7. Start Stellarium ───────────────────────────────────────────────────────
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
echo "INTENTIONALLY MISCONFIGURED: constellation lines ON, art ON, star names OFF, azimuthal grid OFF"
echo "Agent must: set location to (15N, 145W), set date Dec 15 2023 22:30 UTC,"
echo "  fix all 5 display settings, search Polaris/Sirius/Canopus/Vega with screenshots,"
echo "  write nav_log.txt with star names"
