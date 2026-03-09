#!/bin/bash
# Setup script for L-Beam Centroid Statics task
set -e

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Fallback functions if task_utils is missing
if ! type kill_geogebra &>/dev/null; then
    kill_geogebra() { pkill -u "${1:-ga}" -f "geogebra" 2>/dev/null || true; sleep 1; }
    launch_geogebra() { su - "${1:-ga}" -c "DISPLAY=:1 geogebra-classic > /tmp/geogebra_ga.log 2>&1 &" 2>/dev/null || true; }
    wait_for_window() { local w=$1 t=${2:-30} e=0; while [ $e -lt $t ]; do DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "$w" && return 0; sleep 1; e=$((e+1)); done; return 1; }
    focus_geogebra() { local wid=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i geogebra | head -1 | awk '{print $1}'); [ -n "$wid" ] && DISPLAY=:1 wmctrl -i -a "$wid" 2>/dev/null; }
    maximize_geogebra() { local wid=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i geogebra | head -1 | awk '{print $1}'); [ -n "$wid" ] && DISPLAY=:1 wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null; }
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

echo "=== Setting up L-Beam Centroid Task ==="

# 1. Kill existing instances
kill_geogebra ga

# 2. Prepare directories
mkdir -p /home/ga/Documents/GeoGebra/projects
chown -R ga:ga /home/ga/Documents/GeoGebra

# 3. Remove target file if it exists
rm -f /home/ga/Documents/GeoGebra/projects/l_shape_statics.ggb

# 4. Record baseline state
date +%s > /tmp/task_start_time
find /home/ga/Documents/GeoGebra -name "*.ggb" 2>/dev/null | wc -l > /tmp/initial_ggb_count

# 5. Launch GeoGebra
echo "Launching GeoGebra..."
launch_geogebra ga

# 6. Wait for window
if wait_for_window "GeoGebra" 45; then
    echo "GeoGebra started successfully."
    sleep 5
    # Maximize and focus
    maximize_geogebra
    sleep 1
    focus_geogebra
    sleep 1
    
    # Ensure correct initial focus by clicking center
    su - ga -c "DISPLAY=:1 xdotool mousemove 960 540 click 1" 2>/dev/null || true
else
    echo "WARNING: GeoGebra window not detected within timeout."
fi

# 7. Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="