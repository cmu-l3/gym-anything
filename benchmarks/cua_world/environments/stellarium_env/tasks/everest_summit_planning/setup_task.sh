#!/bin/bash
echo "=== Setting up everest_summit_planning task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# ── 1. Terminate any existing instances ───────────────────────────────────────
pkill stellarium 2>/dev/null || true
sleep 2
pkill -9 stellarium 2>/dev/null || true
sleep 1

# ── 2. Create default starting config ─────────────────────────────────────────
# Agent must change location to Everest and modify grids/constellations
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

for section in ['landscape', 'viewing', 'stars', 'navigation', 'location_run_once']:
    if not cfg.has_section(section):
        cfg.add_section(section)

# Starting state: Atmosphere ON, Landscape ON, Grids OFF, Constellation lines ON
cfg.set('landscape', 'flag_atmosphere', 'true')
cfg.set('landscape', 'flag_landscape', 'true')
cfg.set('landscape', 'flag_cardinal_points', 'false') # Agent must turn ON
cfg.set('viewing', 'flag_azimuthal_grid', 'false')    # Agent must turn ON
cfg.set('viewing', 'flag_equatorial_grid', 'false')
cfg.set('viewing', 'flag_constellation_drawing', 'true') # Agent must turn OFF
cfg.set('viewing', 'flag_constellation_art', 'false')

# Default Location: Paris (Agent must change to Everest)
cfg.set('location_run_once', 'latitude', '0.852211')
cfg.set('location_run_once', 'longitude', '0.04084')
cfg.set('location_run_once', 'altitude', '35')
cfg.set('location_run_once', 'home_planet', 'Earth')
cfg.set('location_run_once', 'landscape_name', 'guereins')

with open(config_path, 'w') as f:
    cfg.write(f)
PYEOF

chown -R ga:ga /home/ga/.stellarium

# ── 3. Clean up stale outputs for accurate anti-gaming checks ────────────────
rm -f /home/ga/Desktop/summit_briefing.txt 2>/dev/null || true
mkdir -p /home/ga/Pictures/stellarium
chown -R ga:ga /home/ga/Pictures/stellarium

# Record initial screenshot count
INITIAL_SS_COUNT=$(ls /home/ga/Pictures/stellarium 2>/dev/null | wc -l)
echo "$INITIAL_SS_COUNT" > /tmp/everest_summit_planning_initial_ss_count

# Record task start timestamp
date +%s > /tmp/everest_summit_planning_start_ts

# ── 4. Start Stellarium ───────────────────────────────────────────────────────
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

# ── 5. Capture initial state screenshot ───────────────────────────────────────
DISPLAY=:1 scrot /tmp/everest_summit_planning_start_screenshot.png 2>/dev/null || true

echo "=== Setup Complete ==="