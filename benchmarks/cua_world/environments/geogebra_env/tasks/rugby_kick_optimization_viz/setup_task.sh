#!/bin/bash
# Setup script for Rugby Kick Optimization task

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

echo "=== Setting up Rugby Kick Optimization Task ==="

# 1. Kill existing GeoGebra
kill_geogebra ga
sleep 1

# 2. Prepare Directories
mkdir -p /home/ga/Documents/GeoGebra/projects
mkdir -p /home/ga/Documents/GeoGebra/data
chown -R ga:ga /home/ga/Documents/GeoGebra

# 3. Clean up previous task files
rm -f /home/ga/Documents/GeoGebra/projects/rugby_optimization.ggb 2>/dev/null || true

# 4. Create the data file with the goal dimensions
# This forces the agent to read the file rather than guess
cat > /home/ga/Documents/GeoGebra/data/rugby_dimensions.txt << 'EOF'
RUGBY UNION FIELD DIMENSIONS
Source: World Rugby Laws of the Game

Goal Post Width: 5.6 meters
Crossbar Height: 3.0 meters
EOF
chown ga:ga /home/ga/Documents/GeoGebra/data/rugby_dimensions.txt

# 5. Record Baseline
find /home/ga/Documents/GeoGebra -name "*.ggb" 2>/dev/null | wc -l > /tmp/initial_ggb_count

# 6. Record Start Time (Anti-gaming)
date +%s > /tmp/task_start_time
echo "Task started at: $(cat /tmp/task_start_time)"

# 7. Launch GeoGebra
echo "Launching GeoGebra..."
launch_geogebra ga

if ! wait_for_process "geogebra" 30; then
    echo "WARNING: GeoGebra may not have started"
fi

if ! wait_for_window "GeoGebra" 30; then
    echo "WARNING: GeoGebra window may not have appeared"
fi
sleep 2

# 8. Focus and Optimize Window
su - ga -c "DISPLAY=:1 xdotool mousemove 960 540 click 1" 2>/dev/null || true
sleep 0.5
focus_geogebra
sleep 0.5
maximize_geogebra
sleep 1

# 9. Randomize Viewport
# Prevents agent from blindly clicking coordinates without looking
if [ "${RANDOMIZE_VIEWPORT:-1}" != "0" ]; then
    randomize_geogebra_viewport ga :1
    sleep 0.5
fi

# 10. Initial Screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Rugby Optimization Task Setup Complete ==="
echo ""
echo "TASK: Optimize Rugby Conversion Kick"
echo "  - Data File: ~/Documents/GeoGebra/data/rugby_dimensions.txt"
echo "  - Scenario: Try scored 10m from the goal post."
echo "  - Goal: Find the distance that maximizes the angle between posts."
echo "  - Output: ~/Documents/GeoGebra/projects/rugby_optimization.ggb"