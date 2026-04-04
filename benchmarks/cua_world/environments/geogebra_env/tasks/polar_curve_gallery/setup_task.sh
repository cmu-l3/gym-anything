#!/bin/bash
# Setup script for Polar Curve Gallery task
set -e

# Source utilities if available
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Fallback definitions
if ! type kill_geogebra &>/dev/null; then
    kill_geogebra() { pkill -u "${1:-ga}" -f "geogebra" 2>/dev/null || true; sleep 1; }
    launch_geogebra() { su - "${1:-ga}" -c "DISPLAY=:1 geogebra-classic > /tmp/geogebra_ga.log 2>&1 &" 2>/dev/null || true; }
    wait_for_window() { local w=$1 t=${2:-30} e=0; while [ $e -lt $t ]; do DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "$w" && return 0; sleep 1; e=$((e+1)); done; return 1; }
    focus_geogebra() { local wid=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i geogebra | head -1 | awk '{print $1}'); [ -n "$wid" ] && DISPLAY=:1 wmctrl -i -a "$wid" 2>/dev/null; }
    maximize_geogebra() { local wid=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i geogebra | head -1 | awk '{print $1}'); [ -n "$wid" ] && DISPLAY=:1 wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null; }
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

echo "=== Setting up Polar Curve Gallery Task ==="

# 1. Kill any existing GeoGebra instances
kill_geogebra ga
sleep 1

# 2. Ensure project directory exists and is clean
mkdir -p /home/ga/Documents/GeoGebra/projects
chown -R ga:ga /home/ga/Documents/GeoGebra 2>/dev/null || true
rm -f /home/ga/Documents/GeoGebra/projects/polar_curves.ggb 2>/dev/null || true

# 3. Record task start time (critical for anti-gaming)
date +%s > /tmp/task_start_time
echo "Task started at: $(cat /tmp/task_start_time)"

# 4. Launch GeoGebra with a fresh blank construction
echo "Launching GeoGebra..."
launch_geogebra ga

# 5. Wait for application
sleep 5
if ! wait_for_window "GeoGebra" 45; then
    echo "WARNING: GeoGebra window not detected, retrying launch..."
    launch_geogebra ga
    sleep 10
fi

# 6. Configure window (maximize and focus)
# Click center of screen to ensure focus isn't stuck on a tooltip
su - ga -c "DISPLAY=:1 xdotool mousemove 960 540 click 1" 2>/dev/null || true
sleep 1
focus_geogebra
sleep 0.5
maximize_geogebra
sleep 1

# 7. Dismiss potential startup dialogs/sign-in prompts
su - ga -c "DISPLAY=:1 xdotool key Escape" 2>/dev/null || true
sleep 0.5

# 8. Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="