#!/bin/bash
# Setup script for Sun Path 3D Architecture Tool task
set -e

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Fallback definitions if task_utils.sh unavailable
if ! type kill_geogebra &>/dev/null; then
    kill_geogebra() { pkill -u "${1:-ga}" -f "geogebra" 2>/dev/null || true; sleep 1; }
    launch_geogebra() { su - "${1:-ga}" -c "DISPLAY=:1 geogebra-classic > /tmp/geogebra_ga.log 2>&1 &" 2>/dev/null || true; }
    wait_for_window() { local w=$1 t=${2:-30} e=0; while [ $e -lt $t ]; do DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "$w" && return 0; sleep 1; e=$((e+1)); done; return 1; }
    focus_geogebra() { local wid=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i geogebra | head -1 | awk '{print $1}'); [ -n "$wid" ] && DISPLAY=:1 wmctrl -i -a "$wid" 2>/dev/null; }
    maximize_geogebra() { local wid=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i geogebra | head -1 | awk '{print $1}'); [ -n "$wid" ] && DISPLAY=:1 wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null; }
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

echo "=== Setting up Sun Path Task ==="

# 1. Kill existing GeoGebra
kill_geogebra ga
sleep 1

# 2. Clean/Prepare directories
mkdir -p /home/ga/Documents/GeoGebra/projects
chown -R ga:ga /home/ga/Documents/GeoGebra
rm -f /home/ga/Documents/GeoGebra/projects/seattle_sun_path.ggb 2>/dev/null || true

# 3. Record baseline state
echo "Recording baseline..."
find /home/ga/Documents/GeoGebra -name "*.ggb" 2>/dev/null | wc -l > /tmp/initial_ggb_count
date +%s > /tmp/task_start_time
echo "Task started at: $(cat /tmp/task_start_time)"

# 4. Launch GeoGebra (Standard 2D start - agent must enable 3D)
echo "Launching GeoGebra..."
launch_geogebra ga

# 5. Wait for window
if ! wait_for_window "GeoGebra" 45; then
    echo "WARNING: GeoGebra window did not appear within timeout"
fi
sleep 2

# 6. Focus and Maximize
su - ga -c "DISPLAY=:1 xdotool mousemove 960 540 click 1" 2>/dev/null || true
sleep 0.5
focus_geogebra
sleep 0.5
maximize_geogebra
sleep 1

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="
echo "TASK: Create a 3D Sun Path Diagram for Seattle (47.6 N)"
echo "1. Enable 3D Graphics View"
echo "2. Create 3 paths (Equinox, Summer, Winter)"
echo "3. Tilt the system for Latitude 47.6"
echo "4. Save as 'seattle_sun_path.ggb'"