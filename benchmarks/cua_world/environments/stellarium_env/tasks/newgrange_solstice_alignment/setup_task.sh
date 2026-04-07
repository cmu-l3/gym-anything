#!/bin/bash
echo "=== Setting up newgrange_solstice_alignment task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Fallback screenshot function
if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

TASK_NAME="newgrange_solstice_alignment"

# ── 1. Kill Stellarium and set known starting state ───────────────────────────
echo "--- Resetting Stellarium ---"
pkill stellarium 2>/dev/null || true
sleep 3
pkill -9 stellarium 2>/dev/null || true
sleep 2

# ── 2. Write starting config: atmosphere OFF, landscape ON, azimuthal OFF, cardinal OFF 
#    Agent must toggle ALL of these to reach the correct state.
cp /workspace/config/config.ini /home/ga/.stellarium/config.ini

python3 << 'PYEOF'
import configparser

config_path = "/home/ga/.stellarium/config.ini"
cfg = configparser.RawConfigParser()
cfg.read(config_path)

for section in ['landscape', 'viewing', 'stars', 'navigation', 'location_run_once']:
    if not cfg.has_section(section):
        cfg.add_section(section)

# Starting state:
# atmosphere = OFF (must turn ON)
# landscape = ON (must turn OFF)
# cardinal_points = OFF (must turn ON)
# azimuthal_grid = OFF (must turn ON)
cfg.set('landscape', 'flag_atmosphere', 'false')     
cfg.set('landscape', 'flag_landscape', 'true')      
cfg.set('landscape', 'flag_cardinal_points', 'false') 
cfg.set('viewing', 'flag_azimuthal_grid', 'false')   
cfg.set('viewing', 'flag_equatorial_grid', 'false')
cfg.set('stars', 'flag_star_name', 'true')
cfg.set('navigation', 'startup_time_mode', 'now')
cfg.set('navigation', 'preset_sky_time', '2451545.0')

# Reset location to default (Paris)
cfg.set('location_run_once', 'latitude', '0.8532')
cfg.set('location_run_once', 'longitude', '0.0408')
cfg.set('location_run_once', 'altitude', '35')
cfg.set('location_run_once', 'home_planet', 'Earth')
cfg.set('location_run_once', 'landscape_name', 'guereins')

with open(config_path, 'w') as f:
    cfg.write(f)

print("Config set: atmosphere=OFF, landscape=ON, azimuthal=OFF, cardinal=OFF")
PYEOF

chown ga:ga /home/ga/.stellarium/config.ini

# ── 3. Remove stale output files ──────────────────────────────────────────────
rm -f /home/ga/Desktop/newgrange_alignment_notes.txt 2>/dev/null || true

# ── 4. Create the JSON data file for the agent ────────────────────────────────
mkdir -p /home/ga/data
cat > /home/ga/data/archaeological_sites.json << 'EOF'
{
  "sites": [
    {
      "name": "Newgrange",
      "country": "Ireland",
      "coordinates": {
        "latitude_deg": 53.6947,
        "longitude_deg": -6.4755,
        "altitude_m": 75
      },
      "construction_date_bce": 3200,
      "astronomical_alignment": "Winter solstice sunrise",
      "passage_azimuth_degrees": 135.5
    },
    {
      "name": "Stonehenge",
      "country": "United Kingdom",
      "coordinates": {
        "latitude_deg": 51.1789,
        "longitude_deg": -1.8262,
        "altitude_m": 101
      },
      "construction_date_bce": 3000,
      "astronomical_alignment": "Summer solstice sunrise",
      "passage_azimuth_degrees": 51.2
    }
  ]
}
EOF
chown -R ga:ga /home/ga/data 2>/dev/null || true

# ── 5. Record baseline screenshot count ──────────────────────────────────────
SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
mkdir -p "$SCREENSHOT_DIR"
chown -R ga:ga "$SCREENSHOT_DIR"
INITIAL_SS_COUNT=$(ls "$SCREENSHOT_DIR" 2>/dev/null | wc -l)
echo "$INITIAL_SS_COUNT" > /tmp/${TASK_NAME}_initial_screenshot_count
echo "Initial screenshot count: $INITIAL_SS_COUNT"

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
echo "Agent must configure location to Newgrange, set dates to 3200 BCE and 2024 CE,"
echo "toggle appropriate flags, take screenshots, and write notes."