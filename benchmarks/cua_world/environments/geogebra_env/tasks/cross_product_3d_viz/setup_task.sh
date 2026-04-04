#!/bin/bash
# Setup script for Cross Product 3D Visualization

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Fallback function definitions if task_utils.sh is missing
if ! type launch_geogebra &>/dev/null; then
    launch_geogebra() { su - "${1:-ga}" -c "DISPLAY=:1 geogebra-classic > /tmp/geogebra_ga.log 2>&1 &" 2>/dev/null || true; }
    kill_geogebra() { pkill -u "${1:-ga}" -f "geogebra" 2>/dev/null || true; sleep 1; }
    wait_for_window() { local w=$1 t=${2:-30} e=0; while [ $e -lt $t ]; do DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "$w" && return 0; sleep 1; e=$((e+1)); done; return 1; }
    focus_geogebra() { local wid=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i geogebra | head -1 | awk '{print $1}'); [ -n "$wid" ] && DISPLAY=:1 wmctrl -i -a "$wid" 2>/dev/null; }
    maximize_geogebra() { local wid=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i geogebra | head -1 | awk '{print $1}'); [ -n "$wid" ] && DISPLAY=:1 wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null; }
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

echo "=== Setting up Cross Product 3D Task ==="

# 1. Clean up previous state
kill_geogebra ga
sleep 1

# Ensure project directory exists
mkdir -p /home/ga/Documents/GeoGebra/projects
chown -R ga:ga /home/ga/Documents/GeoGebra

# Remove any existing target file to ensure fresh creation
rm -f /home/ga/Documents/GeoGebra/projects/cross_product_3d.ggb 2>/dev/null || true

# 2. Record task start time (CRITICAL for anti-gaming)
date +%s > /tmp/task_start_time
echo "Task started at: $(cat /tmp/task_start_time)"

# 3. Launch GeoGebra
echo "Launching GeoGebra..."
launch_geogebra ga

# Wait for window
if ! wait_for_window "GeoGebra" 45; then
    echo "WARNING: GeoGebra window did not appear in time"
fi

# 4. Prepare the window
sleep 2
# Click center screen to focus (helps with window manager focus stealing)
su - ga -c "DISPLAY=:1 xdotool mousemove 960 540 click 1" 2>/dev/null || true
sleep 0.5
focus_geogebra
sleep 0.5
maximize_geogebra
sleep 1

# 5. Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Instructions:"
echo "1. Switch to 3D Graphics View (View -> 3D Graphics)"
echo "2. Define vectors u=(1,2,-2) and v=(3,0,1)"
echo "3. Use Cross(u, v) command"
echo "4. Create the parallelogram"
echo "5. Save as ~/Documents/GeoGebra/projects/cross_product_3d.ggb"