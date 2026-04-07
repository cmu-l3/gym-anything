#!/bin/bash
echo "=== Setting up lunar_game_sky_reference task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Fallback screenshot function
if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

TASK_NAME="lunar_game_sky_reference"

# ── 1. Create project data file for the agent ─────────────────────────────────
mkdir -p /home/ga/data
cat > /home/ga/data/lunar_game_project.json << 'EOF'
{
  "project": "Lunar Survival 2030",
  "studio": "Artemis Interactive",
  "description": "Open-world survival game set at a near-future lunar base. Requires accurate sky references for skybox textures, Earth-rise cinematics, and nighttime star navigation gameplay mechanic.",
  "observation_site": {
    "body": "Moon",
    "site_name": "Tranquility Base (Apollo 11 landing site)",
    "selenographic_latitude_deg": 0.6741,
    "selenographic_longitude_deg": 23.4730,
    "source": "NASA LRO / IAU selenographic coordinates"
  },
  "game_datetime_utc": "2030-12-25T12:00:00Z",
  "reference_targets": [
    {
      "object": "Earth",
      "priority": "critical",
      "notes": "Primary visual landmark - Earth as seen from Moon is the game's signature visual element"
    },
    {
      "object": "Saturn",
      "priority": "high",
      "notes": "Rings should be visible through in-game telescope mechanic"
    },
    {
      "object": "wide_starfield",
      "priority": "high",
      "notes": "Full sky reference for procedural skybox generation"
    }
  ],
  "display_requirements": {
    "atmosphere": false,
    "ground": false,
    "constellation_lines": true,
    "constellation_labels": true,
    "planet_labels": true,
    "notes": "Moon has no atmosphere - disable for physical accuracy. Disable ground for full sky dome reference. Enable overlays for art team documentation."
  },
  "output_notes_path": "/home/ga/Desktop/lunar_sky_notes.txt"
}
EOF
chown -R ga:ga /home/ga/data

# ── 2. Kill Stellarium and set known starting state ───────────────────────────
echo "--- Resetting Stellarium ---"
pkill stellarium 2>/dev/null || true
sleep 3
pkill -9 stellarium 2>/dev/null || true
sleep 2

# ── 3. Write starting config: Earth, atmosphere ON, ground ON, no lines ───────
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

# Starting state: Earth, normal daylight/night, no lines
cfg.set('landscape', 'flag_atmosphere', 'true')
cfg.set('landscape', 'flag_landscape', 'true')
cfg.set('viewing', 'flag_constellation_drawing', 'false')
cfg.set('viewing', 'flag_constellation_name', 'false')

# Set location to a standard Earth location (agent must change to Moon)
cfg.set('location_run_once', 'home_planet', 'Earth')
cfg.set('location_run_once', 'latitude', '0.705822')
cfg.set('location_run_once', 'longitude', '-1.396192')
cfg.set('location_run_once', 'altitude', '367')
cfg.set('location_run_once', 'landscape_name', 'guereins')

with open(config_path, 'w') as f:
    cfg.write(f)

print("Config set: Earth view, atmosphere=ON, landscape=ON, lines=OFF")
PYEOF

chown -R ga:ga /home/ga/.stellarium

# ── 4. Clean up outputs from previous runs ────────────────────────────────────
rm -f /home/ga/Desktop/lunar_sky_notes.txt 2>/dev/null || true

SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
mkdir -p "$SCREENSHOT_DIR"
chown -R ga:ga "$SCREENSHOT_DIR"
INITIAL_SS_COUNT=$(ls -1 "$SCREENSHOT_DIR" 2>/dev/null | wc -l)
echo "$INITIAL_SS_COUNT" > /tmp/${TASK_NAME}_initial_screenshot_count
echo "Initial screenshot count: $INITIAL_SS_COUNT"

# ── 5. Record task start timestamp ────────────────────────────────────────────
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

# Dismiss dialogs
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

# ── 7. Take initial screenshot ────────────────────────────────────────────────
take_screenshot /tmp/${TASK_NAME}_start_screenshot.png

echo "=== Setup Complete ==="
echo "Agent starts on Earth with default display settings."
echo "Must configure view for Moon, Tranquility Base, disable atmosphere/ground,"
echo "and enable constellation lines/names before capturing screenshots."