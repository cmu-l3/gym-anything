#!/bin/bash
echo "=== Setting up forensic_sky_reconstruction task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_NAME="forensic_sky_reconstruction"

# 1. Kill any existing Stellarium instance and set a known starting config
echo "--- Resetting Stellarium to known starting state ---"
pkill stellarium 2>/dev/null || true
sleep 3
pkill -9 stellarium 2>/dev/null || true
sleep 2

# 2. Write a fresh config with default settings
# Start state: atmosphere=ON, landscape=ON, planets_labels=OFF, constellation_drawing=OFF
cp /workspace/config/config.ini /home/ga/.stellarium/config.ini

python3 << 'PYEOF'
import configparser

config_path = "/home/ga/.stellarium/config.ini"
cfg = configparser.RawConfigParser()
cfg.read(config_path)

# Ensure sections exist
for section in ['landscape', 'viewing', 'stars', 'navigation', 'location_run_once', 'astro_calc']:
    if not cfg.has_section(section):
        cfg.add_section(section)

# Set known starting state
cfg.set('landscape', 'flag_atmosphere', 'true')
cfg.set('landscape', 'flag_landscape', 'true') # Agent must turn OFF
cfg.set('viewing', 'flag_constellation_drawing', 'false') # Agent must turn ON
cfg.set('stars', 'flag_planets_labels', 'false') # Agent must turn ON
cfg.set('stars', 'flag_planet_names', 'false')
cfg.set('stars', 'flag_star_name', 'false')
cfg.set('navigation', 'startup_time_mode', 'now')

# Reset location to Paris default (agent must change to NYC)
cfg.set('location_run_once', 'latitude', '0.852211')
cfg.set('location_run_once', 'longitude', '0.040854')
cfg.set('location_run_once', 'altitude', '35')
cfg.set('location_run_once', 'home_planet', 'Earth')
cfg.set('location_run_once', 'landscape_name', 'guereins')

with open(config_path, 'w') as f:
    cfg.write(f)

print("Config reset to default starting state")
PYEOF

chown ga:ga /home/ga/.stellarium/config.ini

# 3. Remove stale output files
rm -f /home/ga/Desktop/forensic_sky_report.txt 2>/dev/null || true

# 4. Record baseline screenshot count
SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
mkdir -p "$SCREENSHOT_DIR"
chown -R ga:ga "$SCREENSHOT_DIR"
INITIAL_SS_COUNT=$(ls "$SCREENSHOT_DIR" 2>/dev/null | wc -l)
echo "$INITIAL_SS_COUNT" > /tmp/${TASK_NAME}_initial_screenshot_count

# 5. Record task start timestamp
date +%s > /tmp/task_start_time.txt
echo "Task start timestamp recorded"

# 6. Start Stellarium (Software rendering takes time, starting it for agent saves steps)
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

# Dismiss initial dialogs and maximize
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

# Take initial screenshot
if type take_screenshot &>/dev/null 2>&1; then
    take_screenshot /tmp/task_initial.png
else
    DISPLAY=:1 import -window root "/tmp/task_initial.png" 2>/dev/null || \
    DISPLAY=:1 scrot "/tmp/task_initial.png" 2>/dev/null || true
fi

echo "=== Setup Complete ==="