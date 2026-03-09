#!/bin/bash
# Setup script for Sunflower Phyllotaxis Model task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Fallback function definitions if task_utils.sh is missing
if ! type launch_geogebra &>/dev/null; then
    launch_geogebra() { su - "${1:-ga}" -c "DISPLAY=:1 geogebra-classic > /tmp/geogebra_ga.log 2>&1 &" 2>/dev/null || true; }
    kill_geogebra() { pkill -u "${1:-ga}" -f "geogebra" 2>/dev/null || true; sleep 1; }
    wait_for_window() { local w=$1 t=${2:-30} e=0; while [ $e -lt $t ]; do DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "$w" && return 0; sleep 1; e=$((e+1)); done; return 1; }
    maximize_geogebra() { local wid=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i geogebra | head -1 | awk '{print $1}'); [ -n "$wid" ] && DISPLAY=:1 wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null; }
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

echo "=== Setting up Sunflower Phyllotaxis Task ==="

# 1. Clean up previous runs
kill_geogebra ga
sleep 1

# 2. Prepare directories
mkdir -p /home/ga/Documents/GeoGebra/projects
chown -R ga:ga /home/ga/Documents/GeoGebra 2>/dev/null || true
rm -f /home/ga/Documents/GeoGebra/projects/sunflower_model.ggb 2>/dev/null || true

# 3. Record baseline state
find /home/ga/Documents/GeoGebra -name "*.ggb" 2>/dev/null | wc -l > /tmp/initial_ggb_count
date +%s > /tmp/task_start_time
echo "Task started at: $(cat /tmp/task_start_time)"

# 4. Launch GeoGebra
echo "Launching GeoGebra..."
launch_geogebra ga

# 5. Wait for application
if ! wait_for_window "GeoGebra" 45; then
    echo "WARNING: GeoGebra window did not appear within timeout"
else
    echo "GeoGebra window detected"
fi

sleep 5

# 6. Set up window (Maximize and Focus)
# Click center to ensure focus on the desktop/app
su - ga -c "DISPLAY=:1 xdotool mousemove 960 540 click 1" 2>/dev/null || true
maximize_geogebra
sleep 1

# 7. Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Instructions for Agent:"
echo "1. Create a Slider for the angle (range approx 130-145)."
echo "2. Use the Sequence command to generate >500 points."
echo "3. Formula: r = c*sqrt(n), theta = n*angle."
echo "4. Save as 'sunflower_model.ggb'."