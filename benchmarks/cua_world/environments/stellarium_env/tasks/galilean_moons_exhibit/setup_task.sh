#!/bin/bash
echo "=== Setting up galilean_moons_exhibit task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

TASK_NAME="galilean_moons_exhibit"

# ── 1. Kill Stellarium and set known starting state ───────────────────────────
pkill stellarium 2>/dev/null || true
sleep 3
pkill -9 stellarium 2>/dev/null || true
sleep 2

# ── 2. Write starting config: atmosphere ON, landscape ON, location Pittsburgh ──
# The agent must explicitly disable atmosphere/ground and save the location.
cp /workspace/config/config.ini /home/ga/.stellarium/config.ini 2>/dev/null || touch /home/ga/.stellarium/config.ini

python3 << 'PYEOF'
import configparser

config_path = "/home/ga/.stellarium/config.ini"
cfg = configparser.RawConfigParser()
cfg.read(config_path)

for section in ['landscape', 'viewing', 'stars', 'navigation', 'location_run_once', 'init_location']:
    if not cfg.has_section(section):
        cfg.add_section(section)

# Starting display state (incorrect for this task)
cfg.set('landscape', 'flag_atmosphere', 'true')
cfg.set('landscape', 'flag_landscape', 'true')
cfg.set('stars', 'flag_planets_hints', 'false')

# Starting location (Pittsburgh default)
cfg.set('init_location', 'latitude', '0.705822')
cfg.set('init_location', 'longitude', '-1.396192')
cfg.set('init_location', 'location_name', 'Pittsburgh')

cfg.set('location_run_once', 'latitude', '0.705822')
cfg.set('location_run_once', 'longitude', '-1.396192')

with open(config_path, 'w') as f:
    cfg.write(f)
PYEOF

chown ga:ga /home/ga/.stellarium/config.ini

# ── 3. Clean environment and seed data ─────────────────────────────────────────
rm -f /home/ga/Desktop/galileo_exhibit.txt 2>/dev/null || true

# Pre-populate historical coordinates data
mkdir -p /home/ga/data
cat > /home/ga/data/historical_observatories.json << 'EOF'
[
  {
    "name": "Padua, Italy",
    "description": "Galileo's primary observation site (1592-1610)",
    "latitude": 45.4064,
    "longitude": 11.8768,
    "altitude": 12
  },
  {
    "name": "Uraniborg, Hven",
    "description": "Tycho Brahe's observatory",
    "latitude": 55.9080,
    "longitude": 12.6966,
    "altitude": 45
  }
]
EOF
chown -R ga:ga /home/ga/data

# ── 4. Record baseline screenshot count ──────────────────────────────────────
SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
mkdir -p "$SCREENSHOT_DIR"
chown -R ga:ga "$SCREENSHOT_DIR"
INITIAL_SS_COUNT=$(ls "$SCREENSHOT_DIR" 2>/dev/null | wc -l)
echo "$INITIAL_SS_COUNT" > /tmp/${TASK_NAME}_initial_screenshot_count

# ── 5. Record task start timestamp ───────────────────────────────────────────
date +%s > /tmp/${TASK_NAME}_start_ts

# ── 6. Start Stellarium ───────────────────────────────────────────────────────
su - ga -c "bash /home/ga/start_stellarium.sh"

ELAPSED=0
while [ $ELAPSED -lt 90 ]; do
    WID=$(DISPLAY=:1 xdotool search --name "Stellarium" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
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

take_screenshot /tmp/${TASK_NAME}_start_screenshot.png
echo "=== Setup Complete ==="