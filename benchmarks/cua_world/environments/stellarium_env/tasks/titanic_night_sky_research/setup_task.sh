#!/bin/bash
echo "=== Setting up titanic_night_sky_research task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Fallback screenshot function
if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

TASK_NAME="titanic_night_sky_research"

# ── 1. Kill Stellarium and set a known, INCORRECT starting state ─────────────
echo "--- Resetting Stellarium ---"
pkill stellarium 2>/dev/null || true
sleep 3
pkill -9 stellarium 2>/dev/null || true
sleep 2

# Write starting config: atmosphere OFF, landscape ON, constellations OFF, Paris location
# This forces the agent to manually change all required settings.
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

# Starting state:
cfg.set('landscape', 'flag_atmosphere', 'false')        # Agent must turn ON
cfg.set('landscape', 'flag_landscape', 'true')          # Agent must turn OFF
cfg.set('viewing', 'flag_constellation_drawing', 'false') # Agent must turn ON
cfg.set('viewing', 'flag_constellation_name', 'false')    # Agent must turn ON

# Set location to Paris
cfg.set('location_run_once', 'latitude', '0.852211')
cfg.set('location_run_once', 'longitude', '0.04084')
cfg.set('location_run_once', 'altitude', '35')

with open(config_path, 'w') as f:
    cfg.write(f)

print("Config set to wrong state to force agent to configure properly.")
PYEOF

chown -R ga:ga /home/ga/.stellarium

# ── 2. Create historical data file for the agent ─────────────────────────────
mkdir -p /home/ga/data
cat > /home/ga/data/historical_events.json << 'EOF'
{
  "titanic_collision": {
    "event": "RMS Titanic strikes iceberg",
    "date_utc": "1912-04-15T02:20:00Z",
    "latitude_deg": 41.726,
    "longitude_deg": -50.233,
    "altitude_m": 0,
    "source": "Distress signal coordinates (CQD/SOS) transmitted by wireless operators Phillips and Bride."
  }
}
EOF
chown -R ga:ga /home/ga/data

# ── 3. Remove stale output files ──────────────────────────────────────────────
rm -f /home/ga/Desktop/titanic_sky_research.txt 2>/dev/null || true

# ── 4. Record baseline screenshot count ──────────────────────────────────────
SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
mkdir -p "$SCREENSHOT_DIR"
chown -R ga:ga "$SCREENSHOT_DIR"
INITIAL_SS_COUNT=$(ls -1 "$SCREENSHOT_DIR" 2>/dev/null | wc -l)
echo "$INITIAL_SS_COUNT" > /tmp/${TASK_NAME}_initial_screenshot_count
echo "Initial screenshot count: $INITIAL_SS_COUNT"

# ── 5. Record task start timestamp ───────────────────────────────────────────
date +%s > /tmp/${TASK_NAME}_start_ts

# ── 6. Start Stellarium ───────────────────────────────────────────────────────
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

# Dismiss dialogs & maximize
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

# ── 7. Take initial screenshot ────────────────────────────────────────────────
take_screenshot /tmp/${TASK_NAME}_start_screenshot.png

echo "=== Setup Complete ==="
echo "Agent should see Stellarium open with wrong location and display settings."