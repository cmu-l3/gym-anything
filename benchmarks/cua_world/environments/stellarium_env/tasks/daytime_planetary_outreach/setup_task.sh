#!/bin/bash
echo "=== Setting up daytime_planetary_outreach task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

TASK_NAME="daytime_planetary_outreach"

# ── 1. Kill Stellarium and reset config to known starting state ─────────────
echo "--- Resetting Stellarium ---"
pkill stellarium 2>/dev/null || true
sleep 3
pkill -9 stellarium 2>/dev/null || true
sleep 2

# Write starting config: atmosphere OFF, azimuthal grid OFF, labels OFF.
# Agent MUST turn these ON to complete the task.
cp /workspace/config/config.ini /home/ga/.stellarium/config.ini

python3 << 'PYEOF'
import configparser

config_path = "/home/ga/.stellarium/config.ini"
cfg = configparser.RawConfigParser()
cfg.read(config_path)

for section in ['landscape', 'viewing', 'stars', 'astro', 'navigation', 'location_run_once']:
    if not cfg.has_section(section):
        cfg.add_section(section)

# Starting state:
# atmosphere = OFF (agent must turn ON to see the blue daylight sky)
# azimuthal_grid = OFF (agent must turn ON)
# star_name = OFF (agent must turn ON)
# planets_hints = OFF (agent must turn ON)
cfg.set('landscape', 'flag_atmosphere', 'false')
cfg.set('landscape', 'flag_landscape', 'true')
cfg.set('viewing', 'flag_azimuthal_grid', 'false')
cfg.set('stars', 'flag_star_name', 'false')
cfg.set('astro', 'flag_planets_hints', 'false')
cfg.set('navigation', 'startup_time_mode', 'now')

# Reset location to default (Paris/Pittsburgh)
cfg.set('location_run_once', 'latitude', '0.705822')
cfg.set('location_run_once', 'longitude', '-1.396192')
cfg.set('location_run_once', 'altitude', '367')
cfg.set('location_run_once', 'home_planet', 'Earth')

with open(config_path, 'w') as f:
    cfg.write(f)

print("Config set: atmosphere=OFF, azimuthal=OFF, labels=OFF (agent must configure)")
PYEOF

chown ga:ga /home/ga/.stellarium/config.ini

# ── 2. Remove stale output files ────────────────────────────────────────────
rm -f /home/ga/Desktop/daytime_outreach_plan.txt 2>/dev/null || true

# ── 3. Record baseline screenshot count ─────────────────────────────────────
SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
mkdir -p "$SCREENSHOT_DIR"
chown -R ga:ga "$SCREENSHOT_DIR"
INITIAL_SS_COUNT=$(ls -1 "$SCREENSHOT_DIR" 2>/dev/null | wc -l)
echo "$INITIAL_SS_COUNT" > /tmp/${TASK_NAME}_initial_screenshot_count
echo "Initial screenshot count: $INITIAL_SS_COUNT"

# ── 4. Record task start timestamp ──────────────────────────────────────────
date +%s > /tmp/${TASK_NAME}_start_ts

# ── 5. Start Stellarium ─────────────────────────────────────────────────────
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

# ── 6. Take initial screenshot ──────────────────────────────────────────────
take_screenshot /tmp/${TASK_NAME}_start_screenshot.png

echo "=== Setup Complete ==="
echo "Agent must: set location to Griffith Obs, time to June 4 2023 21:00 UTC,"
echo "turn ON atmosphere, azimuthal grid, star labels, planet labels,"
echo "find Venus, Jupiter, Sirius, capture screenshots, and write the outreach plan."