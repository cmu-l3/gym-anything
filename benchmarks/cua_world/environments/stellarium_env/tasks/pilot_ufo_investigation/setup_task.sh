#!/bin/bash
echo "=== Setting up pilot_ufo_investigation task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null 2>&1; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

TASK_NAME="pilot_ufo_investigation"

# ── 1. Kill Stellarium and set known starting state ───────────────────────────
echo "--- Resetting Stellarium ---"
pkill stellarium 2>/dev/null || true
sleep 3
pkill -9 stellarium 2>/dev/null || true
sleep 2

# ── 2. Write starting config: atmosphere ON, landscape ON, planet labels ON, cardinal points OFF
cp /workspace/config/config.ini /home/ga/.stellarium/config.ini

python3 << 'PYEOF'
import configparser

config_path = "/home/ga/.stellarium/config.ini"
cfg = configparser.RawConfigParser()
cfg.read(config_path)

for section in ['landscape', 'viewing', 'stars', 'astro', 'navigation', 'location_run_once']:
    if not cfg.has_section(section):
        cfg.add_section(section)

# Starting state:
cfg.set('landscape', 'flag_atmosphere', 'true')     # Default ON
cfg.set('landscape', 'flag_landscape', 'true')      # Default ON, must turn OFF
cfg.set('landscape', 'flag_fog', 'false')
cfg.set('landscape', 'flag_cardinal_points', 'false')  # Default OFF, must turn ON
cfg.set('astro', 'flag_planets_labels', 'true')        # Assume ON or agent turns ON
cfg.set('viewing', 'flag_constellation_art', 'false')
cfg.set('viewing', 'flag_azimuthal_grid', 'false')
cfg.set('viewing', 'flag_equatorial_grid', 'false')
cfg.set('viewing', 'flag_constellation_drawing', 'false')
cfg.set('stars', 'flag_star_name', 'true')
cfg.set('navigation', 'startup_time_mode', 'now')
cfg.set('navigation', 'preset_sky_time', '2451545.0')

# Reset location to default (e.g. Pittsburgh or generic)
cfg.set('location_run_once', 'latitude', '0.705822')
cfg.set('location_run_once', 'longitude', '-1.396192')
cfg.set('location_run_once', 'altitude', '367')
cfg.set('location_run_once', 'home_planet', 'Earth')
cfg.set('location_run_once', 'landscape_name', 'guereins')

with open(config_path, 'w') as f:
    cfg.write(f)

print("Config set: default location, atmosphere=ON, landscape=ON")
PYEOF

chown ga:ga /home/ga/.stellarium/config.ini

# ── 3. Remove stale output files ──────────────────────────────────────────────
rm -f /home/ga/Desktop/ufo_investigation_report.txt 2>/dev/null || true

# ── 4. Record baseline screenshot count ──────────────────────────────────────
SCREENSHOT_DIR="/home/ga/Pictures/stellarium"
mkdir -p "$SCREENSHOT_DIR"
chown -R ga:ga "$SCREENSHOT_DIR"
INITIAL_SS_COUNT=$(ls "$SCREENSHOT_DIR" 2>/dev/null | wc -l)
echo "$INITIAL_SS_COUNT" > /tmp/${TASK_NAME}_initial_screenshot_count
echo "Initial screenshot count: $INITIAL_SS_COUNT"

# ── 5. Record task start timestamp ───────────────────────────────────────────
date +%s > /tmp/${TASK_NAME}_start_ts

# ── 6. Take initial screenshot (Stellarium not running yet, just desktop) ─────
take_screenshot /tmp/${TASK_NAME}_start_screenshot.png

echo "=== Setup Complete ==="
echo "Stellarium is not running. Agent must start it, configure location (45N, 40W, 11000m),"
echo "set time to March 5 2023 22:30 UTC, disable landscape, enable cardinal points,"
echo "and find Venus in the SW."