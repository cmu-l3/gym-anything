#!/bin/bash
echo "=== Setting up perseid_meteor_plan task ==="

# 1. Prepare Desktop and data directories
mkdir -p /home/ga/Desktop
mkdir -p /home/ga/data
mkdir -p /home/ga/Pictures/stellarium
rm -f /home/ga/Desktop/perseid_plan.txt
chown -R ga:ga /home/ga/Desktop
chown -R ga:ga /home/ga/data
chown -R ga:ga /home/ga/Pictures

# 2. Generate real-world context data file
cat > /home/ga/data/meteor_showers.json << 'EOF'
{
  "perseids": {
    "name": "Perseids",
    "radiant_constellation": "Perseus",
    "peak_date": "August 12-13",
    "zhr": 100
  },
  "viewing_sites": {
    "flagstaff_dark_sky": {
      "name": "Flagstaff Dark Sky Site (Buffalo Park)",
      "latitude_deg": 35.215,
      "longitude_deg": -111.633,
      "altitude_m": 2130,
      "note": "First International Dark Sky City"
    }
  },
  "event_details": {
    "date_utc": "2024-08-13",
    "peak_viewing_time_utc": "09:00",
    "moon_phase_pct": 56
  }
}
EOF
chown ga:ga /home/ga/data/meteor_showers.json

# 3. Stop existing Stellarium
pkill stellarium 2>/dev/null || true
sleep 2
pkill -9 stellarium 2>/dev/null || true
sleep 1

# 4. Set a known bad starting config (force agent to adjust settings)
python3 << 'PYEOF'
import configparser
import os

config_path = "/home/ga/.stellarium/config.ini"
os.makedirs(os.path.dirname(config_path), exist_ok=True)

cfg = configparser.RawConfigParser()
if os.path.exists(config_path):
    cfg.read(config_path)

for section in ['landscape', 'viewing', 'stars', 'location_run_once']:
    if not cfg.has_section(section):
        cfg.add_section(section)

# Set defaults opposite to task requirements
cfg.set('landscape', 'flag_atmosphere', 'false')
cfg.set('landscape', 'flag_landscape', 'true')
cfg.set('viewing', 'flag_constellation_drawing', 'false')
cfg.set('viewing', 'flag_constellation_name', 'false')

# Set location to Pittsburgh (wrong)
cfg.set('location_run_once', 'latitude', '0.705822')
cfg.set('location_run_once', 'longitude', '-1.396192')
cfg.set('location_run_once', 'altitude', '367')

with open(config_path, 'w') as f:
    cfg.write(f)
PYEOF

chown -R ga:ga /home/ga/.stellarium

# 5. Record baseline screenshot count
find /home/ga/Pictures/stellarium/ -maxdepth 1 -name "*.png" 2>/dev/null | wc -l > /tmp/initial_ss_count

# 6. Launch Stellarium
echo "Starting Stellarium..."
su - ga -c "bash /home/ga/start_stellarium.sh"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Stellarium"; then
        echo "Stellarium window found."
        break
    fi
    sleep 1
done

# Wait for engine to render completely
sleep 10

# Dismiss popups
for i in 1 2; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
done

# Maximize and Focus
DISPLAY=:1 wmctrl -r "Stellarium" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Stellarium" 2>/dev/null || true
sleep 2

# 7. Record Task Start Timestamp and take initial screenshot
date +%s > /tmp/task_start_time.txt
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="