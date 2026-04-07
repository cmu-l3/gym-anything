#!/bin/bash
echo "=== Setting up precession_pole_star_demo task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Fallback screenshot function
if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

TASK_NAME="precession_pole_star_demo"

# ── 1. Kill Stellarium and set known starting state ───────────────────────────
echo "--- Resetting Stellarium to default starting state ---"
pkill stellarium 2>/dev/null || true
sleep 3
pkill -9 stellarium 2>/dev/null || true
sleep 2

# ── 2. Write starting config: atmosphere ON, landscape ON, grids OFF ──────────
# Agent must: turn atmosphere OFF, landscape OFF, equatorial ON, constellation lines ON
cp /workspace/config/config.ini /home/ga/.stellarium/config.ini 2>/dev/null || true

python3 << 'PYEOF'
import configparser
import os

config_path = "/home/ga/.stellarium/config.ini"
if not os.path.exists(os.path.dirname(config_path)):
    os.makedirs(os.path.dirname(config_path), exist_ok=True)

cfg = configparser.RawConfigParser()
if os.path.exists(config_path):
    cfg.read(config_path)

for section in ['landscape', 'viewing', 'stars', 'navigation', 'location_run_once']:
    if not cfg.has_section(section):
        cfg.add_section(section)

# Default starting state
cfg.set('landscape', 'flag_atmosphere', 'true')       # agent must turn OFF
cfg.set('landscape', 'flag_landscape', 'true')        # agent must turn OFF
cfg.set('viewing', 'flag_equatorial_grid', 'false')   # agent must turn ON
cfg.set('viewing', 'flag_constellation_drawing', 'false') # agent must turn ON

# Ensure Stellarium saves the time upon exit
cfg.set('navigation', 'startup_time_mode', 'preset')
cfg.set('navigation', 'preset_sky_time', '2460000.0') # Modern date default

# Reset location to Pittsburgh default
cfg.set('location_run_once', 'latitude', '0.705822')
cfg.set('location_run_once', 'longitude', '-1.396192')
cfg.set('location_run_once', 'altitude', '367')

with open(config_path, 'w') as f:
    cfg.write(f)
print("Config set to modern defaults. Agent must configure ancient Giza parameters.")
PYEOF

chown ga:ga /home/ga/.stellarium/config.ini 2>/dev/null || true

# ── 3. Remove stale output files ──────────────────────────────────────────────
rm -f /home/ga/Desktop/precession_notes.txt 2>/dev/null || true

# ── 4. Record baseline screenshot count ──────────────────────────────────────
SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
mkdir -p "$SCREENSHOT_DIR"
chown -R ga:ga "$SCREENSHOT_DIR"
INITIAL_SS_COUNT=$(ls "$SCREENSHOT_DIR" 2>/dev/null | wc -l)
echo "$INITIAL_SS_COUNT" > /tmp/${TASK_NAME}_initial_screenshot_count

# ── 5. Record task start timestamp ───────────────────────────────────────────
date +%s > /tmp/${TASK_NAME}_start_ts

# ── 6. Start Stellarium ───────────────────────────────────────────────────────
echo "--- Starting Stellarium ---"
su - ga -c "DISPLAY=:1 setsid stellarium > /tmp/stellarium.log 2>&1 &"

ELAPSED=0
while [ $ELAPSED -lt 60 ]; do
    if DISPLAY=:1 wmctrl -l | grep -qi "Stellarium"; then
        echo "Stellarium window found"
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

sleep 8

# Dismiss dialogs and maximize
for i in 1 2; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
done

DISPLAY=:1 wmctrl -r "Stellarium" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "Stellarium" 2>/dev/null || true
sleep 2

# ── 7. Take initial screenshot ────────────────────────────────────────────────
take_screenshot /tmp/${TASK_NAME}_start_screenshot.png

echo "=== Setup Complete ==="