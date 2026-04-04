#!/bin/bash
# Setup script for Linear Transformation Eigenvector Visualization task

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
fi

echo "=== Setting up Linear Transformation Task ==="

# 1. Kill any existing GeoGebra processes to ensure clean slate
kill_geogebra ga
sleep 1

# 2. Prepare directories and clean previous outputs
mkdir -p /home/ga/Documents/GeoGebra/projects
chown -R ga:ga /home/ga/Documents/GeoGebra 2>/dev/null || true
rm -f /home/ga/Documents/GeoGebra/projects/linear_transform_eigen.ggb 2>/dev/null || true

# 3. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time
echo "Task started at: $(cat /tmp/task_start_time)"

# 4. Launch GeoGebra
echo "Launching GeoGebra..."
launch_geogebra ga

# 5. Wait for application to be ready
if ! wait_for_process "geogebra" 30; then
    echo "WARNING: GeoGebra process not found"
fi

if ! wait_for_window "GeoGebra" 45; then
    echo "WARNING: GeoGebra window not detected"
fi

# 6. Ensure window is focused and maximized
sleep 2
# Click on desktop to ensure focus isn't stuck
su - ga -c "DISPLAY=:1 xdotool mousemove 960 540 click 1" 2>/dev/null || true
sleep 0.5
focus_geogebra
sleep 0.5
maximize_geogebra
sleep 1

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="
echo "Instructions:"
echo "1. Create Unit Square: (0,0), (1,0), (1,1), (0,1)"
echo "2. ApplyMatrix({{2,1},{1,2}}, poly1)"
echo "3. Create Eigenvectors for lambda=3 (1,1) and lambda=1 (1,-1)"
echo "4. Add text annotation"
echo "5. Save to ~/Documents/GeoGebra/projects/linear_transform_eigen.ggb"