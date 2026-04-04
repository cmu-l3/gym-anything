#!/bin/bash
# Setup script for Simson Line Construction task
set -e

# Source shared utilities if available
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Fallback definitions if task_utils.sh unavailable
if ! type launch_geogebra &>/dev/null; then
    launch_geogebra() { su - "${1:-ga}" -c "DISPLAY=:1 geogebra-classic > /tmp/geogebra_ga.log 2>&1 &" 2>/dev/null || true; }
    kill_geogebra() { pkill -u "${1:-ga}" -f "geogebra" 2>/dev/null || true; sleep 1; }
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
    focus_geogebra() { local wid=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i geogebra | head -1 | awk '{print $1}'); [ -n "$wid" ] && DISPLAY=:1 wmctrl -i -a "$wid" 2>/dev/null; }
    maximize_geogebra() { local wid=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i geogebra | head -1 | awk '{print $1}'); [ -n "$wid" ] && DISPLAY=:1 wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null; }
    randomize_geogebra_viewport() { true; }
fi

echo "=== Setting up Simson Line Construction Task ==="

# 1. Clean previous state
echo "Cleaning up..."
kill_geogebra ga
rm -rf /home/ga/Documents/GeoGebra/projects/simson_line.ggb 2>/dev/null || true

# 2. Ensure directories exist
mkdir -p /home/ga/Documents/GeoGebra/projects
chown -R ga:ga /home/ga/Documents/GeoGebra

# 3. Record initial state (for anti-gaming)
date +%s > /tmp/task_start_time
echo "Task started at: $(cat /tmp/task_start_time)"
find /home/ga/Documents/GeoGebra -name "*.ggb" 2>/dev/null | wc -l > /tmp/initial_ggb_count

# 4. Launch GeoGebra
echo "Launching GeoGebra..."
launch_geogebra ga

# 5. Wait for application
echo "Waiting for GeoGebra..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "GeoGebra"; then
        echo "GeoGebra window found"
        break
    fi
    sleep 1
done
sleep 5

# 6. Configure window (Maximize & Focus)
su - ga -c "DISPLAY=:1 xdotool mousemove 960 540 click 1" 2>/dev/null || true
sleep 1
focus_geogebra
maximize_geogebra
sleep 1

# 7. Randomize viewport to prevent coordinate gaming (optional but recommended)
if [ "${RANDOMIZE_VIEWPORT:-1}" != "0" ]; then
    echo "Randomizing viewport..."
    randomize_geogebra_viewport ga :1
    sleep 0.5
fi

# 8. Take initial evidence screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Simson Line Task Setup Complete ==="