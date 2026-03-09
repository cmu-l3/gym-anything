#!/bin/bash
# Setup script for Riemann Sum Explorer task
set -e

# Source shared utilities if available
if [ -f "/workspace/scripts/task_utils.sh" ]; then
    source /workspace/scripts/task_utils.sh
else
    # Fallback definitions
    kill_geogebra() { pkill -u "${1:-ga}" -f "geogebra" 2>/dev/null || true; }
    launch_geogebra() { su - "${1:-ga}" -c "DISPLAY=:1 geogebra-classic > /tmp/geogebra_ga.log 2>&1 &" 2>/dev/null || true; }
    wait_for_window() { local w=$1 t=${2:-30} e=0; while [ $e -lt $t ]; do DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "$w" && return 0; sleep 1; e=$((e+1)); done; return 1; }
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

echo "=== Setting up Riemann Sum Explorer Task ==="

# 1. Clean up previous state
kill_geogebra ga
sleep 1

# 2. Ensure project directory exists
mkdir -p /home/ga/Documents/GeoGebra/projects
chown -R ga:ga /home/ga/Documents/GeoGebra 2>/dev/null || true

# 3. Remove target file to prevent false positives from previous runs
rm -f /home/ga/Documents/GeoGebra/projects/riemann_sums.ggb

# 4. Record task start time (Critical for anti-gaming)
date +%s > /tmp/task_start_time
echo "Task started at: $(cat /tmp/task_start_time)"

# 5. Launch GeoGebra
echo "Launching GeoGebra..."
launch_geogebra ga

# 6. Wait for application to be ready
echo "Waiting for GeoGebra window..."
if wait_for_window "GeoGebra" 45; then
    echo "GeoGebra window detected."
else
    echo "WARNING: GeoGebra window not found within timeout."
fi

# 7. Maximize window for visibility
sleep 2
WID=$(DISPLAY=:1 wmctrl -l | grep -i "GeoGebra" | head -n 1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    # Focus the window
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

# 8. Reset mouse to safe position (desktop center)
su - ga -c "DISPLAY=:1 xdotool mousemove 960 540 click 1" 2>/dev/null || true

# 9. Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="