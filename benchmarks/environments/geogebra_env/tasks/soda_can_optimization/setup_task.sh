#!/bin/bash
# Setup script for Soda Can Optimization task

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

echo "=== Setting up Soda Can Optimization Task ==="

# Kill any existing GeoGebra processes
kill_geogebra ga
sleep 1

# Ensure project directory exists
mkdir -p /home/ga/Documents/GeoGebra/projects
chown -R ga:ga /home/ga/Documents/GeoGebra

# Remove any existing file with the expected name (for clean test)
rm -f /home/ga/Documents/GeoGebra/projects/soda_can_opt.ggb 2>/dev/null || true

# Record initial state for verification
echo "0" > /tmp/initial_ggb_count
find /home/ga/Documents/GeoGebra -name "*.ggb" 2>/dev/null | wc -l > /tmp/initial_ggb_count

# Record task start time for timestamp validation (prevents pre-made file attacks)
date +%s > /tmp/task_start_time
echo "Task started at: $(cat /tmp/task_start_time)"

# Launch GeoGebra
echo "Launching GeoGebra..."
launch_geogebra ga

if ! wait_for_process "geogebra" 30; then
    echo "ERROR: GeoGebra failed to start"
fi

if ! wait_for_window "GeoGebra" 30; then
    echo "ERROR: GeoGebra window did not appear"
fi

# Focus and maximize GeoGebra window
focus_geogebra
sleep 0.5
maximize_geogebra
sleep 1

# We want the 3D graphics view to be available, but usually Classic starts in 2D.
# The agent needs to open 3D view themselves, so we don't force it here.
# This adds to the realism of the task.

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Soda Can Optimization Task Setup Complete ==="
echo "Instructions:"
echo "  1. Define V = 355"
echo "  2. Create slider r"
echo "  3. Define h(r) such that Volume is constant"
echo "  4. Define Cost(r) = 2.2*(Top+Bottom Area) + 1.0*(Side Area)"
echo "  5. Minimize Cost and set r to optimum"
echo "  6. Visualize with a 3D Cylinder"
echo "  7. Save as: ~/Documents/GeoGebra/projects/soda_can_opt.ggb"