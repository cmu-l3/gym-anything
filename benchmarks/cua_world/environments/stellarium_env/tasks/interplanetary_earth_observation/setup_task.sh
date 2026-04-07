#!/bin/bash
echo "=== Setting up interplanetary_earth_observation task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

TASK_NAME="interplanetary_earth_observation"

# ── 1. Kill any existing Stellarium instance and set a known starting config ──
echo "--- Resetting Stellarium to known starting state ---"
pkill stellarium 2>/dev/null || true
sleep 3
pkill -9 stellarium 2>/dev/null || true
sleep 2

# ── 2. Write a fresh config with Earth-centric default display settings ────
# Start state: atmosphere=ON, landscape=ON, planet=Earth
# Agent must: change planet=Saturn, atmosphere=OFF, landscape=OFF
cp /workspace/config/config.ini /home/ga/.stellarium/config.ini

python3 << 'PYEOF'
import configparser

config_path = "/home/ga/.stellarium/config.ini"
cfg = configparser.RawConfigParser()
cfg.read(config_path)

# Ensure sections exist
for section in ['landscape', 'viewing', 'stars', 'navigation', 'location_run_once', 'init_location']:
    if not cfg.has_section(section):
        cfg.add_section(section)

# Set known Earth-centric starting state
cfg.set('landscape', 'flag_atmosphere', 'true')   # agent must turn OFF
cfg.set('landscape', 'flag_landscape', 'true')    # agent must turn OFF
cfg.set('viewing', 'flag_planet_names', 'false')  # agent must turn ON
cfg.set('navigation', 'startup_time_mode', 'now')

# Reset location to Earth
cfg.set('location_run_once', 'home_planet', 'Earth')
cfg.set('init_location', 'home_planet', 'Earth')

with open(config_path, 'w') as f:
    cfg.write(f)

print("Config reset to default starting state (Earth-centric)")
PYEOF

chown ga:ga /home/ga/.stellarium/config.ini

# ── 3. Remove any stale output files ────────
rm -f /home/ga/Desktop/cassini_exhibit.txt 2>/dev/null || true

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

if [ $ELAPSED -ge 90 ]; then
    echo "WARNING: Stellarium window not detected within 90s"
fi

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
take_screenshot /tmp/${TASK_NAME}_start_screenshot.png

echo "=== Setup Complete ==="
echo "Starting state: Planet=Earth, atmosphere=ON, ground=ON"
echo "Agent must: set Planet to Saturn, date to July 19 2013 21:27 UTC, disable atmosphere, disable ground, take screenshot, write exhibit notes."