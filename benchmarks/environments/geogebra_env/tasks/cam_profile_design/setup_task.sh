#!/bin/bash
# Setup script for Cam Profile Design task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Fallback functions if task_utils not available
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

echo "=== Setting up Cam Profile Design Task ==="

# 1. Clean environment
kill_geogebra ga
sleep 1
mkdir -p /home/ga/Documents/GeoGebra/projects
chown -R ga:ga /home/ga/Documents/GeoGebra

# Remove target file if it exists
rm -f /home/ga/Documents/GeoGebra/projects/cam_profile.ggb

# 2. Record initial state
find /home/ga/Documents/GeoGebra -name "*.ggb" 2>/dev/null | wc -l > /tmp/initial_ggb_count
date +%s > /tmp/task_start_time
echo "Task started at: $(cat /tmp/task_start_time)"

# 3. Launch Application
echo "Launching GeoGebra..."
launch_geogebra ga

# 4. Wait for readiness
if ! wait_for_process "geogebra" 30; then
    echo "WARNING: GeoGebra process not found"
fi
if ! wait_for_window "GeoGebra" 30; then
    echo "WARNING: GeoGebra window not found"
fi
sleep 5

# 5. Configure UI (Focus and Maximize)
# Click center to ensure focus on the desktop/app
su - ga -c "DISPLAY=:1 xdotool mousemove 960 540 click 1" 2>/dev/null || true
sleep 0.5
focus_geogebra
sleep 0.5
maximize_geogebra
sleep 1

# 6. Anti-cheat: Randomize viewport
if [ "${RANDOMIZE_VIEWPORT:-1}" != "0" ]; then
    randomize_geogebra_viewport ga :1
    sleep 0.5
fi

# 7. Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Instructions:"
echo "1. Define the displacement function for the cam (0-90 Dwell, 90-180 Rise, 180-270 Dwell, 270-360 Return)."
echo "2. Use R=3 for base circle, Lift=2."
echo "3. Use the Curve command to create the profile."
echo "4. Save as ~/Documents/GeoGebra/projects/cam_profile.ggb"