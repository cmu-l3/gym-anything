#!/bin/bash
# Setup script for Optics Refraction task
set -e

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

echo "=== Setting up Optics Refraction Task ==="

# 1. Clean environment
kill_geogebra ga
sleep 1
mkdir -p /home/ga/Documents/GeoGebra/projects
chown -R ga:ga /home/ga/Documents/GeoGebra
rm -f /home/ga/Documents/GeoGebra/projects/refraction_lab.ggb 2>/dev/null || true

# 2. Record start time for anti-gaming
date +%s > /tmp/task_start_time
echo "Task started at: $(cat /tmp/task_start_time)"

# 3. Launch GeoGebra
echo "Launching GeoGebra..."
launch_geogebra ga

# 4. Wait for application
if wait_for_window "GeoGebra" 45; then
    echo "GeoGebra window detected"
    sleep 5
    # Ensure window is usable
    focus_geogebra
    sleep 0.5
    maximize_geogebra
else
    echo "WARNING: GeoGebra window not found, but continuing setup"
fi

# 5. Capture initial state
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Instructions:"
echo "1. Create sliders 'n1' and 'n2' (Index of Refraction)"
echo "2. Create a light source and incident ray"
echo "3. Calculate refraction angle using Snell's Law: n1*sin(t1) = n2*sin(t2)"
echo "4. Visualize the refracted ray (and handle Total Internal Reflection)"
echo "5. Save as 'refraction_lab.ggb' in ~/Documents/GeoGebra/projects/"