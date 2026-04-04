#!/bin/bash
# Setup script for Hurricane Katrina Track Analysis task

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

echo "=== Setting up Hurricane Katrina Track Analysis Task ==="

# 1. Clean up previous sessions
kill_geogebra ga
sleep 1
rm -f /home/ga/Documents/GeoGebra/projects/katrina_analysis.ggb 2>/dev/null || true

# 2. Prepare Data Directory
mkdir -p /home/ga/Documents/GeoGebra/data
mkdir -p /home/ga/Documents/GeoGebra/projects
chown -R ga:ga /home/ga/Documents/GeoGebra

# 3. Create the CSV Data File
# Data source: NOAA NHC HURDAT2 (Simplified for task)
CSV_FILE="/home/ga/Documents/GeoGebra/data/katrina_track.csv"
cat > "$CSV_FILE" << 'CSVEOF'
Date,Latitude,Longitude,WindSpeed_mph
23-Aug,23.1,-75.1,35
24-Aug,24.5,-76.5,40
25-Aug,26.0,-79.0,60
26-Aug,25.4,-81.3,80
27-Aug,24.6,-83.3,105
28-Aug,25.9,-88.1,165
29-Aug,28.2,-89.6,140
30-Aug,32.6,-89.1,35
CSVEOF
chown ga:ga "$CSV_FILE"
echo "Created data file at $CSV_FILE"

# 4. Record initial state
date +%s > /tmp/task_start_time
echo "Task started at: $(cat /tmp/task_start_time)"

# 5. Launch GeoGebra
echo "Launching GeoGebra..."
launch_geogebra ga

if ! wait_for_process "geogebra" 30; then
    echo "WARNING: GeoGebra process not found"
fi

if ! wait_for_window "GeoGebra" 45; then
    echo "WARNING: GeoGebra window not found"
fi
sleep 2

# 6. Configure Window
# Click to ensure focus on desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 960 540 click 1" 2>/dev/null || true
sleep 0.5
focus_geogebra
sleep 0.5
maximize_geogebra
sleep 1

# 7. Randomize viewport (optional, prevents coordinate memorization)
if [ "${RANDOMIZE_VIEWPORT:-1}" != "0" ]; then
    randomize_geogebra_viewport ga :1
    sleep 0.5
fi

# 8. Take initial evidence
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Task: Import '$CSV_FILE', create track Polyline, calculate distance in km."