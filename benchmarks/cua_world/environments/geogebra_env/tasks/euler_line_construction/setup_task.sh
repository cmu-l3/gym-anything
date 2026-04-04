#!/bin/bash
# Setup script for Euler Line Construction task
set -e

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Fallback functions if task_utils not available
if ! type kill_geogebra &>/dev/null; then
    kill_geogebra() { pkill -u "${1:-ga}" -f "geogebra" 2>/dev/null || true; sleep 1; }
    launch_geogebra() { su - "${1:-ga}" -c "DISPLAY=:1 geogebra-classic > /tmp/geogebra_ga.log 2>&1 &" 2>/dev/null || true; }
    wait_for_window() { local w=$1 t=${2:-30} e=0; while [ $e -lt $t ]; do DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "$w" && return 0; sleep 1; e=$((e+1)); done; return 1; }
    focus_geogebra() { local wid=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i geogebra | head -1 | awk '{print $1}'); [ -n "$wid" ] && DISPLAY=:1 wmctrl -i -a "$wid" 2>/dev/null; }
    maximize_geogebra() { local wid=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i geogebra | head -1 | awk '{print $1}'); [ -n "$wid" ] && DISPLAY=:1 wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null; }
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
    randomize_geogebra_viewport() { true; }
fi

echo "=== Setting up Euler Line Construction Task ==="

# 1. Clean up previous state
kill_geogebra ga
sleep 1

# 2. Prepare directories
mkdir -p /home/ga/Documents/GeoGebra/projects
chown -R ga:ga /home/ga/Documents/GeoGebra

# 3. Remove target file if it exists
rm -f /home/ga/Documents/GeoGebra/projects/euler_line.ggb

# 4. Record start time (Anti-gaming)
date +%s > /tmp/task_start_time
echo "Task started at: $(cat /tmp/task_start_time)"

# 5. Launch GeoGebra
echo "Launching GeoGebra..."
launch_geogebra ga

# 6. Wait for application
if ! wait_for_window "GeoGebra" 45; then
    echo "WARNING: GeoGebra window did not appear within timeout"
fi
sleep 2

# 7. Configure window
su - ga -c "DISPLAY=:1 xdotool mousemove 960 540 click 1" 2>/dev/null || true
sleep 0.5
focus_geogebra
sleep 0.5
maximize_geogebra
sleep 1

# 8. Randomize viewport (Prevent coordinate caching/blind clicking)
if [ "${RANDOMIZE_VIEWPORT:-1}" != "0" ]; then
    randomize_geogebra_viewport ga :1
    sleep 0.5
fi

# 9. Initial evidence
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Instructions:"
echo "1. Construct triangle A(1,1), B(7,2), C(4,6)"
echo "2. Construct Centroid, Circumcenter, Orthocenter"
echo "3. Draw the Euler Line through them"
echo "4. Add text annotation"
echo "5. Save as ~/Documents/GeoGebra/projects/euler_line.ggb"