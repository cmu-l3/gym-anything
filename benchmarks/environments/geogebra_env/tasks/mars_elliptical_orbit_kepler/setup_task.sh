#!/bin/bash
# Setup script for Mars Elliptical Orbit task

# Source shared utilities if available
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Fallback definitions if task_utils.sh unavailable
if ! type kill_geogebra &>/dev/null; then
    kill_geogebra() { pkill -u "${1:-ga}" -f "geogebra" 2>/dev/null || true; sleep 1; }
    launch_geogebra() { su - "${1:-ga}" -c "DISPLAY=:1 geogebra-classic > /tmp/geogebra_ga.log 2>&1 &" 2>/dev/null || true; }
    wait_for_process() { local p=$1 t=${2:-30} e=0; while [ $e -lt $t ]; do pgrep -f "$p" > /dev/null 2>&1 && return 0; sleep 1; e=$((e+1)); done; return 1; }
    wait_for_window() { local w=$1 t=${2:-30} e=0; while [ $e -lt $t ]; do DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "$w" && return 0; sleep 1; e=$((e+1)); done; return 1; }
    focus_geogebra() { local wid=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i geogebra | head -1 | awk '{print $1}'); [ -n "$wid" ] && DISPLAY=:1 wmctrl -i -a "$wid" 2>/dev/null; }
    maximize_geogebra() { local wid=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i geogebra | head -1 | awk '{print $1}'); [ -n "$wid" ] && DISPLAY=:1 wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null; }
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
    randomize_geogebra_viewport() { true; }
fi

echo "=== Setting up Mars Orbit Task ==="

# 1. Clean environment
kill_geogebra ga
sleep 1
mkdir -p /home/ga/Documents/GeoGebra/projects
chown -R ga:ga /home/ga/Documents/GeoGebra
rm -f /home/ga/Documents/GeoGebra/projects/mars_orbit.ggb 2>/dev/null || true

# 2. Record anti-gaming timestamps
date +%s > /tmp/task_start_time
echo "Task started at: $(cat /tmp/task_start_time)"

# 3. Launch Application
echo "Launching GeoGebra..."
launch_geogebra ga

if ! wait_for_process "geogebra" 30; then
    echo "ERROR: GeoGebra failed to start"
    exit 1
fi

if ! wait_for_window "GeoGebra" 30; then
    echo "ERROR: GeoGebra window did not appear"
    exit 1
fi

# 4. Configure Window
sleep 2
# Click center to focus desktop/app
su - ga -c "DISPLAY=:1 xdotool mousemove 960 540 click 1" 2>/dev/null || true
sleep 0.5
focus_geogebra
sleep 0.5
maximize_geogebra
sleep 1

# 5. Randomize viewport to prevent coordinate hardcoding
# (Agent must zoom/pan to find origin or use commands)
if [ "${RANDOMIZE_VIEWPORT:-1}" != "0" ]; then
    echo "Randomizing viewport..."
    randomize_geogebra_viewport ga :1
    sleep 0.5
fi

# 6. Take evidence screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Instructions:"
echo "1. Create Sun at (0,0)"
echo "2. Create Earth orbit (Circle, r=1)"
echo "3. Create Mars orbit (Ellipse, a=1.524, e=0.0934)"
echo "   Hint: You need to calculate c = a*e to find the second focus."
echo "4. Label Perihelion and Aphelion"
echo "5. Add eccentricity text label"
echo "6. Save as mars_orbit.ggb"