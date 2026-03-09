#!/bin/bash
# Setup script for Newton's Method Root Viz task

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

echo "=== Setting up Newton's Method Task ==="

# 1. Clean environment
kill_geogebra ga
sleep 1

# 2. Prepare directories
mkdir -p /home/ga/Documents/GeoGebra/projects
chown -R ga:ga /home/ga/Documents/GeoGebra 2>/dev/null || true

# 3. Remove target file if exists (to ensure new creation)
rm -f /home/ga/Documents/GeoGebra/projects/newtons_method.ggb 2>/dev/null || true

# 4. Record baseline state
date +%s > /tmp/task_start_time
find /home/ga/Documents/GeoGebra -name "*.ggb" 2>/dev/null | wc -l > /tmp/initial_ggb_count

# 5. Launch GeoGebra
echo "Launching GeoGebra..."
launch_geogebra ga

if ! wait_for_process "geogebra" 30; then
    echo "ERROR: GeoGebra process not found"
    # Try one retry
    launch_geogebra ga
    sleep 5
fi

if ! wait_for_window "GeoGebra" 30; then
    echo "WARNING: GeoGebra window not detected (might be unnamed)"
fi

# 6. Configure Window
sleep 2
# Click center to focus desktop/app
su - ga -c "DISPLAY=:1 xdotool mousemove 960 540 click 1" 2>/dev/null || true
sleep 0.5

focus_geogebra
maximize_geogebra
sleep 1

# 7. Randomize viewport to prevent coordinate gaming
# (Agent must zoom/pan to find the function at x=3)
if [ "${RANDOMIZE_VIEWPORT:-1}" != "0" ]; then
    randomize_geogebra_viewport ga :1
fi

# 8. Initial evidence
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Instructions:"
echo "1. Input: f(x) = x^3 - 2x - 5"
echo "2. Input: Derivative(f)"
echo "3. Construct Newton iteration from x0=3"
echo "4. Save to: ~/Documents/GeoGebra/projects/newtons_method.ggb"