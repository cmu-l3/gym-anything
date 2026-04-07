#!/bin/bash
echo "=== Setting up historical_true_crime_sky task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Fallback screenshot function if utilities are missing
if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

TASK_NAME="historical_true_crime_sky"

# ── 1. Kill Stellarium and set known starting state ───────────────────────────
echo "--- Resetting Stellarium to baseline ---"
pkill stellarium 2>/dev/null || true
sleep 3
pkill -9 stellarium 2>/dev/null || true
sleep 2

# ── 2. Write starting config ──────────────────────────────────────────────────
# Atmosphere ON, Landscape ON, Azimuthal OFF, Cardinal Points OFF
# Location set to a default (e.g., Paris) to force agent to navigate.
cp /workspace/config/config.ini /home/ga/.stellarium/config.ini

python3 << 'PYEOF'
import configparser

config_path = "/home/ga/.stellarium/config.ini"
cfg = configparser.RawConfigParser()
cfg.read(config_path)

for section in ['landscape', 'viewing', 'stars', 'navigation', 'location_run_once']:
    if not cfg.has_section(section):
        cfg.add_section(section)

# Set starting display state
cfg.set('landscape', 'flag_atmosphere', 'true')
cfg.set('landscape', 'flag_landscape', 'true')
cfg.set('landscape', 'flag_cardinal_points', 'false') # Agent must turn ON
cfg.set('viewing', 'flag_azimuthal_grid', 'false')    # Agent must turn ON
cfg.set('viewing', 'flag_equatorial_grid', 'false')
cfg.set('navigation', 'startup_time_mode', 'now')

# Set location to Paris (agent must change to London)
cfg.set('location_run_once', 'latitude', '0.8522')
cfg.set('location_run_once', 'longitude', '0.0410')
cfg.set('location_run_once', 'altitude', '35')

with open(config_path, 'w') as f:
    cfg.write(f)
PYEOF

chown ga:ga /home/ga/.stellarium/config.ini

# ── 3. Clean up stale files ───────────────────────────────────────────────────
rm -f /home/ga/Desktop/whitechapel_moon.txt 2>/dev/null || true

# ── 4. Record baseline screenshot count and task start time ───────────────────
SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
mkdir -p "$SCREENSHOT_DIR"
chown -R ga:ga "$SCREENSHOT_DIR"
INITIAL_SS_COUNT=$(ls "$SCREENSHOT_DIR" 2>/dev/null | wc -l)
echo "$INITIAL_SS_COUNT" > /tmp/${TASK_NAME}_initial_screenshot_count

date +%s > /tmp/${TASK_NAME}_start_ts
echo "Task start timestamp recorded"

# ── 5. Start Stellarium ───────────────────────────────────────────────────────
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

# Dismiss any dialogs
for i in 1 2; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
done

# Maximize and Focus
DISPLAY=:1 wmctrl -r "Stellarium" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

WID=$(DISPLAY=:1 xdotool search --name "Stellarium" 2>/dev/null | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 xdotool windowactivate "$WID" 2>/dev/null || true
    DISPLAY=:1 xdotool windowfocus "$WID" 2>/dev/null || true
fi
sleep 2

# ── 6. Take initial screenshot ────────────────────────────────────────────────
take_screenshot /tmp/${TASK_NAME}_start_screenshot.png

echo "=== Setup Complete ==="