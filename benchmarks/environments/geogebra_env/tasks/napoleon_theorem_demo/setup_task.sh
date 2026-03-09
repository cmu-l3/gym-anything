#!/bin/bash
# Setup script for Napoleon's Theorem task
set -e

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Fallback functions if task_utils missing
if ! type kill_geogebra &>/dev/null; then
    kill_geogebra() { pkill -u "${1:-ga}" -f "geogebra" 2>/dev/null || true; sleep 1; }
    launch_geogebra() { su - "${1:-ga}" -c "DISPLAY=:1 geogebra-classic > /tmp/geogebra_ga.log 2>&1 &" 2>/dev/null || true; }
    wait_for_window() { local w=$1 t=${2:-30} e=0; while [ $e -lt $t ]; do DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "$w" && return 0; sleep 1; e=$((e+1)); done; return 1; }
    focus_geogebra() { local wid=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i geogebra | head -1 | awk '{print $1}'); [ -n "$wid" ] && DISPLAY=:1 wmctrl -i -a "$wid" 2>/dev/null; }
    maximize_geogebra() { local wid=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i geogebra | head -1 | awk '{print $1}'); [ -n "$wid" ] && DISPLAY=:1 wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null; }
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

echo "=== Setting up Napoleon's Theorem Task ==="

# 1. clean up previous state
kill_geogebra ga
sleep 1

# 2. Prepare directories
mkdir -p /home/ga/Documents/GeoGebra/projects
chown -R ga:ga /home/ga/Documents/GeoGebra

# 3. Remove target file if exists (to ensure new creation)
rm -f /home/ga/Documents/GeoGebra/projects/napoleon_theorem.ggb 2>/dev/null || true

# 4. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time
echo "Task started at: $(cat /tmp/task_start_time)"

# 5. Launch GeoGebra
echo "Launching GeoGebra..."
launch_geogebra ga

# 6. Wait for window and setup view
if wait_for_window "GeoGebra" 45; then
    echo "GeoGebra window found."
    sleep 2
    focus_geogebra
    sleep 1
    maximize_geogebra
    sleep 1
    
    # Optional: Randomize viewport slightly to prevent absolute coordinate replay attacks
    # (Agent must visually locate origin)
    su - ga -c "DISPLAY=:1 xdotool mousemove 500 500 click 4" 2>/dev/null || true # Zoom in slightly
else
    echo "WARNING: GeoGebra window not found within timeout."
fi

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Instructions:"
echo "1. Construct triangle A(0,0), B(6,0), C(2,5)"
echo "2. Construct external equilateral triangles on sides"
echo "3. Connect centroids of equilateral triangles"
echo "4. Save as 'napoleon_theorem.ggb'"