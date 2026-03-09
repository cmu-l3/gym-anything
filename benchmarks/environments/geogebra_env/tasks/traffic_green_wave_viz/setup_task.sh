#!/bin/bash
# Setup script for Traffic Green Wave Visualization task
set -o pipefail

# Source shared utilities if available
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

echo "=== Setting up Traffic Green Wave Task ==="

# 1. Clean up previous state
kill_geogebra ga
sleep 1

# 2. Prepare directories
mkdir -p /home/ga/Documents/GeoGebra/projects
chown -R ga:ga /home/ga/Documents/GeoGebra

# Remove existing target file to ensure new creation
rm -f /home/ga/Documents/GeoGebra/projects/green_wave.ggb 2>/dev/null || true

# 3. Record baseline for verification
date +%s > /tmp/task_start_time
echo "Task started at: $(cat /tmp/task_start_time)"

# 4. Launch GeoGebra
echo "Launching GeoGebra..."
launch_geogebra ga

# Wait for window
if ! wait_for_window "GeoGebra" 45; then
    echo "WARNING: GeoGebra window not found after timeout"
fi
sleep 2

# 5. Optimize window state
# Click center to ensure focus on correct desktop/layer
su - ga -c "DISPLAY=:1 xdotool mousemove 960 540 click 1" 2>/dev/null || true
sleep 0.5
focus_geogebra
maximize_geogebra
sleep 1

# 6. Capture initial state
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task Setup Complete ==="
echo "TASK INSTRUCTIONS:"
echo "1. Create a slider 'offset'"
echo "2. Create signals at y=0, 80, 160, 240, 320"
echo "3. Use Sequence command for periodic red lights (Cycle=60s)"
echo "4. Plot car trajectory y = 11.2x"
echo "5. Save to ~/Documents/GeoGebra/projects/green_wave.ggb"