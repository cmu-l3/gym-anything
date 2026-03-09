#!/bin/bash
# Setup script for Analemmatic Sundial task

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

echo "=== Setting up Analemmatic Sundial Task ==="

# Kill any existing GeoGebra processes
kill_geogebra ga
sleep 1

# Ensure project directory exists
mkdir -p /home/ga/Documents/GeoGebra/projects
chown -R ga:ga /home/ga/Documents/GeoGebra 2>/dev/null || true

# Remove any existing file with the expected name (for clean test)
rm -f /home/ga/Documents/GeoGebra/projects/sundial_chicago.ggb 2>/dev/null || true

# Record initial state for verification
find /home/ga/Documents/GeoGebra -name "*.ggb" 2>/dev/null | wc -l > /tmp/initial_ggb_count

# Record task start time for timestamp validation
date +%s > /tmp/task_start_time
echo "Task started at: $(cat /tmp/task_start_time)"

# Launch GeoGebra
echo "Launching GeoGebra..."
launch_geogebra ga

# Wait for window
if ! wait_for_window "GeoGebra" 45; then
    echo "WARNING: GeoGebra window may not have appeared"
fi

# Setup window
sleep 2
su - ga -c "DISPLAY=:1 xdotool mousemove 960 540 click 1" 2>/dev/null || true
sleep 0.5
focus_geogebra
sleep 0.5
maximize_geogebra
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Instructions:"
echo "1. Design an analemmatic sundial for Chicago (Lat 41.88 N)"
echo "2. Semi-major axis a = 6"
echo "3. Calculate semi-minor axis b = a * sin(lat)"
echo "4. Create the hour marker ellipse"
echo "5. Mark Noon (0,b), 3 PM, and 9 AM"
echo "6. Mark Summer/Winter solstice on the date strip: y = a * tan(23.44) * cos(lat)"
echo "7. Save as ~/Documents/GeoGebra/projects/sundial_chicago.ggb"