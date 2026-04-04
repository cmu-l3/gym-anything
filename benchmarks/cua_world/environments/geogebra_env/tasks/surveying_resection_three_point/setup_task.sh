#!/bin/bash
# Setup script for Surveying Resection task

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

echo "=== Setting up Surveying Resection Task ==="

# 1. Clean up previous state
kill_geogebra ga
sleep 1

mkdir -p /home/ga/Documents/GeoGebra/projects
chown -R ga:ga /home/ga/Documents/GeoGebra 2>/dev/null || true

# Remove any existing solution file
rm -f /home/ga/Documents/GeoGebra/projects/resection_solution.ggb 2>/dev/null || true

# 2. Record baseline
date +%s > /tmp/task_start_time
echo "Task started at: $(cat /tmp/task_start_time)"

# 3. Launch GeoGebra
echo "Launching GeoGebra..."
launch_geogebra ga

if ! wait_for_window "GeoGebra" 60; then
    echo "WARNING: GeoGebra window may not have appeared"
fi
sleep 2

# 4. Focus and maximize
su - ga -c "DISPLAY=:1 xdotool mousemove 960 540 click 1" 2>/dev/null || true
sleep 0.5
focus_geogebra
sleep 0.5
maximize_geogebra
sleep 1

# 5. Set up viewport roughly centered on the problem area
# The points range from -300 to 400. Default view is usually -10 to 10.
# We need to zoom out significantly.
echo "Adjusting viewport..."
# Using scroll wheel to zoom out (click 5 is scroll down/out)
# Need roughly 10-15 clicks to get from radius 10 to radius 500+
for i in {1..12}; do
    su - ga -c "DISPLAY=:1 xdotool click 5" 2>/dev/null || true
    sleep 0.1
done
sleep 1

# 6. Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Surveying Resection Task Setup Complete ==="
echo ""
echo "TASK: Three-Point Resection (Snellius-Pothenot)"
echo "-------------------------------------------------"
echo "Landmarks (meters):"
echo "  A = (-300, 200)"
echo "  B = (100, 500)"
echo "  C = (400, -100)"
echo ""
echo "Measurements from P:"
echo "  Angle APB = 40 deg"
echo "  Angle BPC = 70 deg"
echo ""
echo "Instructions:"
echo "1. Plot A, B, C."
echo "2. Construct locus circles for the angles."
echo "3. Find intersection P."
echo "4. Verify with angle measurements."
echo "5. Save as 'resection_solution.ggb'."