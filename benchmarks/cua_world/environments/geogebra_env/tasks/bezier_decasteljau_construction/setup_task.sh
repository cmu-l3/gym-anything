#!/bin/bash
# Setup script for Bézier Curve de Casteljau Construction task
set -o pipefail

# Define fallback functions if task_utils.sh is missing (for safety)
if [ -f "/workspace/scripts/task_utils.sh" ]; then
    source /workspace/scripts/task_utils.sh
else
    kill_geogebra() { pkill -u "${1:-ga}" -f "geogebra" 2>/dev/null || true; }
    launch_geogebra() { su - "${1:-ga}" -c "DISPLAY=:1 geogebra-classic > /tmp/geogebra_ga.log 2>&1 &" 2>/dev/null || true; }
    wait_for_window() { local w=$1 t=${2:-30} e=0; while [ $e -lt $t ]; do DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "$w" && return 0; sleep 1; e=$((e+1)); done; return 1; }
    focus_geogebra() { local wid=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i geogebra | head -1 | awk '{print $1}'); [ -n "$wid" ] && DISPLAY=:1 wmctrl -i -a "$wid" 2>/dev/null; }
    maximize_geogebra() { local wid=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i geogebra | head -1 | awk '{print $1}'); [ -n "$wid" ] && DISPLAY=:1 wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null; }
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

echo "=== Setting up Bézier Curve Task ==="

# 1. clean up environment
kill_geogebra ga
sleep 1

# Ensure directories exist
mkdir -p /home/ga/Documents/GeoGebra/projects
chown -R ga:ga /home/ga/Documents/GeoGebra

# Remove target file if it exists (fresh start)
rm -f /home/ga/Documents/GeoGebra/projects/bezier_decasteljau.ggb 2>/dev/null || true

# 2. Record anti-gaming timestamps
date +%s > /tmp/task_start_time
echo "Task started at: $(cat /tmp/task_start_time)"

# 3. Launch GeoGebra
echo "Launching GeoGebra..."
launch_geogebra ga

if ! wait_for_window "GeoGebra" 45; then
    echo "WARNING: GeoGebra window did not appear within timeout"
fi
sleep 3

# 4. Set window state
# Click center to ensure focus/desktop active
su - ga -c "DISPLAY=:1 xdotool mousemove 960 540 click 1" 2>/dev/null || true
sleep 1

focus_geogebra
sleep 0.5
maximize_geogebra
sleep 1

# 5. Capture initial state
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Instructions:"
echo "1. Create Control Points: P0(0,0), P1(1,3), P2(4,3), P3(5,0)"
echo "2. Create Slider t (0 to 1)"
echo "3. Build the de Casteljau construction (segments & intermediate points)"
echo "4. Create the Curve trace"
echo "5. Save as 'bezier_decasteljau.ggb' in ~/Documents/GeoGebra/projects/"