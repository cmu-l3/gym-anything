#!/bin/bash
# Setup script for Ship Stability Metacenter Analysis
set -e

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Fallback definitions if task_utils.sh is missing (for safety)
if ! type launch_geogebra &>/dev/null; then
    launch_geogebra() { su - "${1:-ga}" -c "DISPLAY=:1 geogebra-classic > /tmp/geogebra_ga.log 2>&1 &" 2>/dev/null || true; }
    kill_geogebra() { pkill -u "${1:-ga}" -f "geogebra" 2>/dev/null || true; }
    wait_for_window() { local w=$1 t=${2:-30} e=0; while [ $e -lt $t ]; do DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "$w" && return 0; sleep 1; e=$((e+1)); done; return 1; }
    focus_geogebra() { local wid=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i geogebra | head -1 | awk '{print $1}'); [ -n "$wid" ] && DISPLAY=:1 wmctrl -i -a "$wid" 2>/dev/null; }
    maximize_geogebra() { local wid=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i geogebra | head -1 | awk '{print $1}'); [ -n "$wid" ] && DISPLAY=:1 wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null; }
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

echo "=== Setting up Ship Stability Task ==="

# 1. Clean up previous run
kill_geogebra ga
sleep 1
mkdir -p /home/ga/Documents/GeoGebra/projects
chown -R ga:ga /home/ga/Documents/GeoGebra
rm -f /home/ga/Documents/GeoGebra/projects/barge_stability.ggb

# 2. Record start time for anti-gaming verification
date +%s > /tmp/task_start_time

# 3. Launch GeoGebra
echo "Launching GeoGebra..."
launch_geogebra ga
sleep 5

# 4. Wait for window and setup UI
if wait_for_window "GeoGebra" 45; then
    echo "GeoGebra started."
    sleep 2
    focus_geogebra
    sleep 0.5
    maximize_geogebra
    sleep 1
    
    # Dismiss any startup dialogs (Esc key)
    su - ga -c "DISPLAY=:1 xdotool key Escape" 2>/dev/null || true
else
    echo "WARNING: GeoGebra window not found."
fi

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="