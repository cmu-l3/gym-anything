#!/bin/bash
# Setup script for Inscribed Angle Theorem Demo task
set -euo pipefail

# Source shared utilities if available
if [ -f "/workspace/scripts/task_utils.sh" ]; then
    source /workspace/scripts/task_utils.sh
else
    # Fallback minimal definitions
    kill_geogebra() { pkill -u "${1:-ga}" -f "geogebra" 2>/dev/null || true; }
    launch_geogebra() { su - "${1:-ga}" -c "DISPLAY=:1 geogebra-classic > /tmp/geogebra_ga.log 2>&1 &" 2>/dev/null || true; }
    wait_for_process() { local p=$1 t=${2:-30} e=0; while [ $e -lt $t ]; do pgrep -f "$p" > /dev/null 2>&1 && return 0; sleep 1; e=$((e+1)); done; return 1; }
    wait_for_window() { local w=$1 t=${2:-30} e=0; while [ $e -lt $t ]; do DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "$w" && return 0; sleep 1; e=$((e+1)); done; return 1; }
    focus_geogebra() { local wid=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i geogebra | head -1 | awk '{print $1}'); [ -n "$wid" ] && DISPLAY=:1 wmctrl -i -a "$wid" 2>/dev/null; }
    maximize_geogebra() { local wid=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i geogebra | head -1 | awk '{print $1}'); [ -n "$wid" ] && DISPLAY=:1 wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null; }
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

echo "=== Setting up Inscribed Angle Theorem Task ==="

# 1. Kill any existing GeoGebra processes
kill_geogebra ga
sleep 1

# 2. Ensure project directory exists
mkdir -p /home/ga/Documents/GeoGebra/projects
chown -R ga:ga /home/ga/Documents/GeoGebra

# 3. Clean up previous task artifacts
rm -f /home/ga/Documents/GeoGebra/projects/inscribed_angle.ggb
rm -f /tmp/task_result.json

# 4. Record initial state baseline
find /home/ga/Documents/GeoGebra -name "*.ggb" 2>/dev/null | wc -l > /tmp/initial_ggb_count

# 5. Record task start time (CRITICAL for anti-gaming)
date +%s > /tmp/task_start_time
echo "Task started at: $(cat /tmp/task_start_time)"

# 6. Launch GeoGebra with a blank canvas
echo "Launching GeoGebra..."
launch_geogebra ga

# 7. Wait for application
if ! wait_for_process "geogebra" 30; then
    echo "ERROR: GeoGebra failed to start"
    exit 1
fi

if ! wait_for_window "GeoGebra" 45; then
    echo "ERROR: GeoGebra window did not appear"
    exit 1
fi

# 8. Configure window
sleep 2
# Click center to ensure focus on desktop/app
su - ga -c "DISPLAY=:1 xdotool mousemove 960 540 click 1" 2>/dev/null || true
sleep 0.5
focus_geogebra
sleep 0.5
maximize_geogebra
sleep 1

# 9. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Instructions:"
echo "1. Construct circle at (0,0) radius 3"
echo "2. Place points A(3,0), B(0,3) and moveable point C on circle"
echo "3. Measure angles ACB and AOB"
echo "4. Add text annotation"
echo "5. Save as inscribed_angle.ggb"