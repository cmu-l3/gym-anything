#!/bin/bash
echo "=== Setting up traffic_sun_glare_investigation task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Fallback screenshot function
if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

TASK_NAME="traffic_sun_glare_investigation"

# ── 1. Kill Stellarium and reset configuration to baseline ──────────────────
echo "--- Resetting Stellarium ---"
pkill stellarium 2>/dev/null || true
sleep 3
pkill -9 stellarium 2>/dev/null || true
sleep 2

# Write baseline config
# Start state: atmosphere ON, landscape ON, azimuthal grid OFF, cardinal OFF
# The agent must ensure atmosphere/landscape stay ON, and turn azimuthal/cardinal ON.
cp /workspace/config/config.ini /home/ga/.stellarium/config.ini

python3 << 'PYEOF'
import configparser

config_path = "/home/ga/.stellarium/config.ini"
cfg = configparser.RawConfigParser()
cfg.read(config_path)

for section in ['landscape', 'viewing', 'stars', 'navigation', 'location_run_once']:
    if not cfg.has_section(section):
        cfg.add_section(section)

# Set starting flags
cfg.set('landscape', 'flag_atmosphere', 'true')
cfg.set('landscape', 'flag_landscape', 'true')
cfg.set('landscape', 'flag_cardinal_points', 'false')
cfg.set('viewing', 'flag_azimuthal_grid', 'false')
cfg.set('viewing', 'flag_equatorial_grid', 'false')

# Default location (Paris) to force the agent to change it to NYC
cfg.set('location_run_once', 'latitude', '0.8522')
cfg.set('location_run_once', 'longitude', '0.0410')
cfg.set('location_run_once', 'altitude', '35')
cfg.set('location_run_once', 'home_planet', 'Earth')

with open(config_path, 'w') as f:
    cfg.write(f)

print("Config set: default location, atmosphere=ON, landscape=ON, azimuthal=OFF")
PYEOF

chown ga:ga /home/ga/.stellarium/config.ini

# ── 2. Remove stale outputs and record baseline screenshots ────────────────
rm -f /home/ga/Desktop/glare_investigation_report.txt 2>/dev/null || true

SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
mkdir -p "$SCREENSHOT_DIR"
chown -R ga:ga "$SCREENSHOT_DIR"
INITIAL_SS_COUNT=$(ls "$SCREENSHOT_DIR" 2>/dev/null | wc -l)
echo "$INITIAL_SS_COUNT" > /tmp/${TASK_NAME}_initial_screenshot_count

# ── 3. Create forensic data file for the agent ─────────────────────────────
mkdir -p /home/ga/data
cat > /home/ga/data/crash_report_ny.json << 'EOF'
{
  "incident_id": "NYPD-2023-08921",
  "location": "Manhattan, New York",
  "latitude": 40.750,
  "longitude": -73.996,
  "date_utc": "2023-07-13",
  "time_utc": "00:20:00",
  "driver_statement": "I was driving westbound along the street grid (heading 299 degrees). The sun was directly in my eyes, completely blinding me right before the collision.",
  "investigation_request": "Verify if the sun's azimuth was near 299 degrees at this exact time and location."
}
EOF
chown -R ga:ga /home/ga/data

# ── 4. Record task start timestamp ─────────────────────────────────────────
date +%s > /tmp/${TASK_NAME}_start_ts

# ── 5. Start Stellarium ────────────────────────────────────────────────────
echo "--- Starting Stellarium ---"
su - ga -c "bash /home/ga/start_stellarium.sh"

# Wait for window
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

# Maximize
DISPLAY=:1 wmctrl -r "Stellarium" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Focus
WID=$(DISPLAY=:1 xdotool search --name "Stellarium" 2>/dev/null | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 xdotool windowactivate "$WID" 2>/dev/null || true
    DISPLAY=:1 xdotool windowfocus "$WID" 2>/dev/null || true
fi
sleep 2

# ── 6. Take initial screenshot ──────────────────────────────────────────────
take_screenshot /tmp/${TASK_NAME}_start_screenshot.png

echo "=== Setup Complete ==="