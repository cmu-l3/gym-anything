#!/bin/bash
# Setup script for Bicycle Geometry Trail Calculator task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Fallback definitions if task_utils.sh unavailable
if ! type kill_geogebra &>/dev/null; then
    kill_geogebra() { pkill -u "${1:-ga}" -f "geogebra" 2>/dev/null || true; sleep 1; }
    launch_geogebra() { su - "${1:-ga}" -c "DISPLAY=:1 geogebra-classic > /tmp/geogebra_ga.log 2>&1 &" 2>/dev/null || true; }
    wait_for_process() { local p=$1 t=${2:-30} e=0; while [ $e -lt $t ]; do pgrep -f "$p" > /dev/null 2>&1 && return 0; sleep 1; e=$((e+1)); done; return 1; }
    wait_for_window() { local w=$1 t=${2:-30} e=0; while [ $e -lt $t ]; do DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "$w" && return 0; sleep 1; e=$((e+1)); done; return 1; }
    focus_geogebra() { local wid=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i geogebra | head -1 | awk '{print $1}'); [ -n "$wid" ] && DISPLAY=:1 wmctrl -i -a "$wid" 2>/dev/null; }
    maximize_geogebra() { local wid=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i geogebra | head -1 | awk '{print $1}'); [ -n "$wid" ] && DISPLAY=:1 wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null; }
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
    randomize_geogebra_viewport() { true; }
fi

echo "=== Setting up Bicycle Geometry Task ==="

# Kill any existing GeoGebra processes
kill_geogebra ga
sleep 1

# Ensure project directory exists
mkdir -p /home/ga/Documents/GeoGebra/projects
chown -R ga:ga /home/ga/Documents/GeoGebra 2>/dev/null || true

# Remove any existing file with the expected name (for clean test)
rm -f /home/ga/Documents/GeoGebra/projects/bicycle_trail.ggb 2>/dev/null || true

# Record task start time for timestamp validation (prevents pre-made file attacks)
date +%s > /tmp/task_start_time
echo "Task started at: $(cat /tmp/task_start_time)"

# Launch GeoGebra
echo "Launching GeoGebra..."
launch_geogebra ga

if ! wait_for_process "geogebra" 30; then
    echo "WARNING: GeoGebra may not have started"
fi

if ! wait_for_window "GeoGebra" 30; then
    echo "WARNING: GeoGebra window may not have appeared"
fi

# Click on center of the screen to select current desktop (focus helper)
su - ga -c "DISPLAY=:1 xdotool mousemove 960 540 click 1" 2>/dev/null || true
sleep 1

# Focus and maximize GeoGebra window
focus_geogebra
sleep 0.5
maximize_geogebra
sleep 1

# Randomize viewport to prevent pre-computed coordinate attacks
if [ "${RANDOMIZE_VIEWPORT:-1}" != "0" ]; then
    echo "Randomizing viewport..."
    randomize_geogebra_viewport ga :1
    sleep 0.5
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Bicycle Geometry Task Setup Complete ==="
echo "Specifications:"
echo "  - Wheel Radius: 370 mm"
echo "  - Head Angle: 67 deg"
echo "  - Fork Offset: 44 mm"
echo "  - Save file: ~/Documents/GeoGebra/projects/bicycle_trail.ggb"