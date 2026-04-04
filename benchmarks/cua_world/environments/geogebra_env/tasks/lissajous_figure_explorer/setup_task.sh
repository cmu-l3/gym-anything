#!/bin/bash
# Setup script for Lissajous Figure Explorer task
set -e

# Source shared utilities if available
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

echo "=== Setting up Lissajous Figure Explorer Task ==="

# 1. Clean up environment
kill_geogebra ga
sleep 1

# 2. Ensure project directory exists
mkdir -p /home/ga/Documents/GeoGebra/projects
chown -R ga:ga /home/ga/Documents/GeoGebra

# 3. Remove any previous task artifacts (crucial for valid verification)
rm -f /home/ga/Documents/GeoGebra/projects/lissajous_explorer.ggb 2>/dev/null || true

# 4. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time
echo "Task started at: $(cat /tmp/task_start_time)"

# 5. Launch GeoGebra
echo "Launching GeoGebra..."
launch_geogebra ga

# 6. Wait for application
count=0
while [ $count -lt 45 ]; do
    if DISPLAY=:1 wmctrl -l | grep -i "GeoGebra"; then
        break
    fi
    sleep 1
    count=$((count+1))
done

# 7. Configure window (Maximize and Focus)
sleep 2
su - ga -c "DISPLAY=:1 xdotool mousemove 960 540 click 1" 2>/dev/null || true
maximize_geogebra
sleep 1
focus_geogebra
sleep 1

# 8. Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "GeoGebra is open with a blank construction."