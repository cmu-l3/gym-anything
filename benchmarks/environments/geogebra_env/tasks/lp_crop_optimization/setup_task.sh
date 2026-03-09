#!/bin/bash
# Setup script for LP Crop Optimization task
set -o pipefail

# Define shared utilities if not available
if [ -f "/workspace/scripts/task_utils.sh" ]; then
    source /workspace/scripts/task_utils.sh
else
    # Fallback definitions
    kill_geogebra() { pkill -u "${1:-ga}" -f "geogebra" 2>/dev/null || true; sleep 1; }
    launch_geogebra() { su - "${1:-ga}" -c "DISPLAY=:1 geogebra-classic > /tmp/geogebra_ga.log 2>&1 &" 2>/dev/null || true; }
    wait_for_process() { local p=$1 t=${2:-30} e=0; while [ $e -lt $t ]; do pgrep -f "$p" > /dev/null 2>&1 && return 0; sleep 1; e=$((e+1)); done; return 1; }
    wait_for_window() { local w=$1 t=${2:-30} e=0; while [ $e -lt $t ]; do DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "$w" && return 0; sleep 1; e=$((e+1)); done; return 1; }
    focus_geogebra() { local wid=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i geogebra | head -1 | awk '{print $1}'); [ -n "$wid" ] && DISPLAY=:1 wmctrl -i -a "$wid" 2>/dev/null; }
    maximize_geogebra() { local wid=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i geogebra | head -1 | awk '{print $1}'); [ -n "$wid" ] && DISPLAY=:1 wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null; }
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

echo "=== Setting up LP Crop Optimization Task ==="

# 1. Clean up previous sessions
kill_geogebra ga
sleep 1

# 2. Prepare directories
mkdir -p /home/ga/Documents/GeoGebra/projects
chown -R ga:ga /home/ga/Documents/GeoGebra 2>/dev/null || true

# 3. Remove any existing result file (anti-gaming)
rm -f /home/ga/Documents/GeoGebra/projects/crop_optimization.ggb 2>/dev/null || true

# 4. Record task start time (CRITICAL for verification)
date +%s > /tmp/task_start_time
echo "Task started at: $(cat /tmp/task_start_time)"

# 5. Launch GeoGebra
echo "Launching GeoGebra..."
launch_geogebra ga

if ! wait_for_process "geogebra" 45; then
    echo "WARNING: GeoGebra process not found"
fi

if ! wait_for_window "GeoGebra" 45; then
    echo "WARNING: GeoGebra window not found"
fi

sleep 5

# 6. Configure UI (Maximize and Focus)
# Click center screen to ensure focus
su - ga -c "DISPLAY=:1 xdotool mousemove 960 540 click 1" 2>/dev/null || true
sleep 1
focus_geogebra
sleep 1
maximize_geogebra
sleep 1

# 7. Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== LP Crop Optimization Task Setup Complete ==="
echo ""
echo "TASK: Create a Linear Programming visualization."
echo "  - Maximize P = 250x + 200y"
echo "  - Constraints: x+y<=240, 2x+y<=400, x+3y<=480"
echo "  - Mark corner points and feasible region"
echo "  - Annotate optimal solution (160, 80)"
echo "  - Save as: ~/Documents/GeoGebra/projects/crop_optimization.ggb"