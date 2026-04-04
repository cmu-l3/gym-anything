#!/bin/bash
set -e
echo "=== Setting up Archimedes Pi Polygon Exhaustion task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Fallback functions if task_utils.sh is missing
if ! type kill_geogebra &>/dev/null; then
    kill_geogebra() { pkill -u "${1:-ga}" -f "geogebra" 2>/dev/null || true; sleep 1; }
    launch_geogebra() { su - "${1:-ga}" -c "DISPLAY=:1 geogebra-classic > /tmp/geogebra_ga.log 2>&1 &" 2>/dev/null || true; }
    wait_for_window() { local w=$1 t=${2:-30} e=0; while [ $e -lt $t ]; do DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "$w" && return 0; sleep 1; e=$((e+1)); done; return 1; }
    focus_geogebra() { local wid=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i geogebra | head -1 | awk '{print $1}'); [ -n "$wid" ] && DISPLAY=:1 wmctrl -i -a "$wid" 2>/dev/null; }
    maximize_geogebra() { local wid=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i geogebra | head -1 | awk '{print $1}'); [ -n "$wid" ] && DISPLAY=:1 wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null; }
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

# Kill any existing GeoGebra processes
kill_geogebra ga

# Ensure output directory exists and is clean
mkdir -p /home/ga/Documents/GeoGebra/projects
rm -f /home/ga/Documents/GeoGebra/projects/archimedes_pi.ggb
chown -R ga:ga /home/ga/Documents/GeoGebra

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task started at: $(cat /tmp/task_start_time.txt)"

# Launch GeoGebra with a blank construction
echo "Launching GeoGebra..."
launch_geogebra ga

# Wait for GeoGebra window to appear
if ! wait_for_window "GeoGebra" 45; then
    echo "WARNING: GeoGebra window did not appear in time."
fi

# Maximize and focus GeoGebra
sleep 2
maximize_geogebra
sleep 1
focus_geogebra
sleep 1

# Dismiss any startup dialogs (like login prompts)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="