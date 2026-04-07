#!/bin/bash
echo "=== Setting up tombaugh_pluto_discovery task ==="

TASK_NAME="tombaugh_pluto_discovery"

# ── 1. Kill any existing Stellarium instance ──────────────────────────────────
echo "--- Resetting Stellarium ---"
pkill stellarium 2>/dev/null || true
sleep 3
pkill -9 stellarium 2>/dev/null || true
sleep 2

# ── 2. Write a modern-day starting config ─────────────────────────────────────
# We want the agent to do ALL the work: disable atmosphere/ground, enable grid,
# disable nebulae, and set the location/date completely from scratch.
cp /workspace/config/config.ini /home/ga/.stellarium/config.ini

python3 << 'PYEOF'
import configparser

config_path = "/home/ga/.stellarium/config.ini"
cfg = configparser.RawConfigParser()
cfg.read(config_path)

for section in ['landscape', 'viewing', 'stars', 'astrocalc', 'navigation', 'location_run_once']:
    if not cfg.has_section(section):
        cfg.add_section(section)

# Starting state (modern day, messy display):
cfg.set('landscape', 'flag_atmosphere', 'true')     # Agent must turn OFF
cfg.set('landscape', 'flag_landscape', 'true')      # Agent must turn OFF
cfg.set('viewing', 'flag_equatorial_grid', 'false') # Agent must turn ON
cfg.set('astrocalc', 'flag_nebula', 'true')         # Agent must turn OFF
cfg.set('stars', 'flag_star_name', 'true')
cfg.set('navigation', 'startup_time_mode', 'now')   # Modern day

# Reset location to Pittsburgh default
cfg.set('location_run_once', 'latitude', '0.705822')
cfg.set('location_run_once', 'longitude', '-1.396192')
cfg.set('location_run_once', 'altitude', '367')
cfg.set('location_run_once', 'home_planet', 'Earth')
cfg.set('location_run_once', 'landscape_name', 'guereins')

with open(config_path, 'w') as f:
    cfg.write(f)

print("Config set to modern day, Pittsburgh, with atmosphere and ground ON.")
PYEOF

chown ga:ga /home/ga/.stellarium/config.ini

# ── 3. Clean up stale outputs to ensure anti-gaming ───────────────────────────
rm -f /home/ga/Desktop/tombaugh_exhibit.txt 2>/dev/null || true

# ── 4. Record baseline screenshot count ───────────────────────────────────────
SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
mkdir -p "$SCREENSHOT_DIR"
chown -R ga:ga "$SCREENSHOT_DIR"
INITIAL_SS_COUNT=$(ls -1 "$SCREENSHOT_DIR" 2>/dev/null | wc -l)
echo "$INITIAL_SS_COUNT" > /tmp/${TASK_NAME}_initial_screenshot_count

# ── 5. Record task start timestamp ────────────────────────────────────────────
date +%s > /tmp/${TASK_NAME}_start_ts

# ── 6. Take an initial screenshot (Desktop) ───────────────────────────────────
sleep 1
DISPLAY=:1 scrot /tmp/${TASK_NAME}_start_screenshot.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/${TASK_NAME}_start_screenshot.png 2>/dev/null || true

echo "=== Setup Complete ==="
echo "Agent must: launch Stellarium, set location to Flagstaff, date to Jan 1930,"
echo "turn OFF atmosphere/ground/nebulae, turn ON equatorial grid, capture 2 screens,"
echo "and write the exhibit text file."