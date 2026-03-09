#!/bin/bash
# Setup script for Least Squares Visualizer task

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

echo "=== Setting up Least Squares Visualizer Task ==="

# Kill any existing GeoGebra processes
kill_geogebra ga
sleep 1

# Ensure project directory exists
mkdir -p /home/ga/Documents/GeoGebra/projects
chown -R ga:ga /home/ga/Documents/GeoGebra 2>/dev/null || true

# Remove any existing target file (clean test)
rm -f /home/ga/Documents/GeoGebra/projects/least_squares.ggb 2>/dev/null || true

# Record task start time (for timestamp validation)
date +%s > /tmp/task_start_time
echo "Task started at: $(cat /tmp/task_start_time)"

# Launch GeoGebra
echo "Launching GeoGebra..."
launch_geogebra ga

# Wait for application to start
sleep 5
if ! wait_for_window "GeoGebra" 60; then
    echo "WARNING: GeoGebra window may not have appeared"
fi

# Focus and maximize
su - ga -c "DISPLAY=:1 xdotool mousemove 960 540 click 1" 2>/dev/null || true
sleep 1
focus_geogebra
sleep 0.5
maximize_geogebra
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Least Squares Visualizer Setup Complete ==="
echo ""
echo "TASK INSTRUCTIONS:"
echo "1. Plot points: (1,2), (2,3), (3,5), (4,4), (5,7)"
echo "2. Create a moveable 'guess' line"
echo "3. Visualize residuals as SQUARES attached to the vertical distance"
echo "4. Calculate the sum of these square areas"
echo "5. Add the actual FitLine"
echo "6. Save to ~/Documents/GeoGebra/projects/least_squares.ggb"