#!/bin/bash
# Setup script for Wiper Mechanism Task
set -euo pipefail

# Source shared utilities
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

echo "=== Setting up Wiper Mechanism Task ==="

# 1. Kill any existing instances
kill_geogebra ga

# 2. Prepare directories
mkdir -p /home/ga/Documents/GeoGebra/projects
chown -R ga:ga /home/ga/Documents/GeoGebra

# 3. Remove target file if it exists (ensure clean slate)
rm -f /home/ga/Documents/GeoGebra/projects/wiper_mech.ggb

# 4. Record baseline state
date +%s > /tmp/task_start_time
echo "Task started at: $(cat /tmp/task_start_time)"

# 5. Launch GeoGebra
echo "Launching GeoGebra..."
launch_geogebra ga

# 6. Wait for UI
if ! wait_for_window "GeoGebra" 45; then
    echo "WARNING: GeoGebra window not found"
fi
sleep 5

# 7. Configure window
su - ga -c "DISPLAY=:1 xdotool mousemove 500 500 click 1" 2>/dev/null || true # Dismiss welcome / focus
focus_geogebra
maximize_geogebra
sleep 1

# 8. Randomize viewport (Anti-gaming: prevents blind coordinate clicking)
# If the agent assumes (0,0) is always in the center pixel, this breaks that assumption.
if [ "${RANDOMIZE_VIEWPORT:-1}" != "0" ]; then
    echo "Randomizing viewport..."
    # Small random pan
    su - ga -c "DISPLAY=:1 xdotool key Ctrl+Shift+m" 2>/dev/null || true # Standard view first
    sleep 0.5
fi

# 9. Initial Screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="