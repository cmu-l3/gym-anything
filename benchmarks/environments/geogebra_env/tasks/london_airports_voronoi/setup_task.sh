#!/bin/bash
# Setup script for London Airports Voronoi task
set -o pipefail

# Source shared utilities if available
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Fallback definitions
if ! type kill_geogebra &>/dev/null; then
    kill_geogebra() { pkill -u "${1:-ga}" -f "geogebra" 2>/dev/null || true; sleep 1; }
    launch_geogebra() { su - "${1:-ga}" -c "DISPLAY=:1 geogebra-classic > /tmp/geogebra_ga.log 2>&1 &" 2>/dev/null || true; }
    wait_for_process() { local p=$1 t=${2:-30} e=0; while [ $e -lt $t ]; do pgrep -f "$p" > /dev/null 2>&1 && return 0; sleep 1; e=$((e+1)); done; return 1; }
    wait_for_window() { local w=$1 t=${2:-30} e=0; while [ $e -lt $t ]; do DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "$w" && return 0; sleep 1; e=$((e+1)); done; return 1; }
    focus_geogebra() { local wid=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i geogebra | head -1 | awk '{print $1}'); [ -n "$wid" ] && DISPLAY=:1 wmctrl -i -a "$wid" 2>/dev/null; }
    maximize_geogebra() { local wid=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i geogebra | head -1 | awk '{print $1}'); [ -n "$wid" ] && DISPLAY=:1 wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null; }
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

echo "=== Setting up London Airports Voronoi Task ==="

# 1. Clean up environment
kill_geogebra ga
sleep 1
mkdir -p /home/ga/Documents/GeoGebra/projects
chown -R ga:ga /home/ga/Documents/GeoGebra
rm -f /home/ga/Documents/GeoGebra/projects/london_airports_voronoi.ggb 2>/dev/null || true

# 2. Record baseline state
find /home/ga/Documents/GeoGebra -name "*.ggb" 2>/dev/null | wc -l > /tmp/initial_ggb_count
date +%s > /tmp/task_start_time
echo "Task started at: $(cat /tmp/task_start_time)"

# 3. Launch GeoGebra
echo "Launching GeoGebra..."
launch_geogebra ga

if ! wait_for_process "geogebra" 30; then
    echo "WARNING: GeoGebra process not found"
fi

if ! wait_for_window "GeoGebra" 45; then
    echo "WARNING: GeoGebra window not found"
fi
sleep 2

# 4. Prepare UI
# Focus and maximize
su - ga -c "DISPLAY=:1 xdotool mousemove 500 500 click 1" 2>/dev/null || true
focus_geogebra
sleep 0.5
maximize_geogebra
sleep 1

# Zoom out slightly to ensure user realizes the scale (coordinates go up to 60)
# We don't want to do the work for them, but starting at standard zoom (-10 to 10) 
# might make them think nothing is plotting. 
# However, the task requires them to handle the view, so we leave default zoom
# to test their ability to zoom out/fit view.

# 5. Capture initial state
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Instructions:"
echo "1. Plot the 6 airports (e.g. LHR=(-26,3), LGW=(-2,-42), etc.)"
echo "2. Create a List of these points"
echo "3. Use the Voronoi command on the list"
echo "4. Add label 'Service Areas'"
echo "5. Save as 'london_airports_voronoi.ggb'"