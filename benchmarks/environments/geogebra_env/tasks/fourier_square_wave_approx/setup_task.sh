#!/bin/bash
# Setup script for Fourier Square Wave Approximation task
set -e

# Source utilities if available, otherwise define minimal
if [ -f "/workspace/scripts/task_utils.sh" ]; then
    source /workspace/scripts/task_utils.sh
else
    # Fallback definitions
    kill_geogebra() { pkill -u "${1:-ga}" -f "geogebra" 2>/dev/null || true; }
    launch_geogebra() { su - "${1:-ga}" -c "DISPLAY=:1 geogebra-classic > /tmp/geogebra_ga.log 2>&1 &" 2>/dev/null || true; }
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

echo "=== Setting up Fourier Square Wave Task ==="

# 1. Clean up environment
echo "Cleaning previous state..."
kill_geogebra ga
sleep 1

# Ensure project directory exists and is clean
PROJECT_DIR="/home/ga/Documents/GeoGebra/projects"
mkdir -p "$PROJECT_DIR"
chown -R ga:ga "/home/ga/Documents/GeoGebra" 2>/dev/null || true
rm -f "$PROJECT_DIR/fourier_square_wave.ggb" 2>/dev/null || true

# 2. Record initial state
date +%s > /tmp/task_start_time
echo "Task started at: $(cat /tmp/task_start_time)"

# 3. Launch GeoGebra
echo "Launching GeoGebra..."
launch_geogebra ga

# Wait for application
echo "Waiting for GeoGebra to load..."
for i in {1..30}; do
    if pgrep -f "geogebra" > /dev/null; then
        echo "GeoGebra process found."
        break
    fi
    sleep 1
done
sleep 5 # Extra time for GUI

# 4. Window management
# Click center to ensure focus/desktop active
su - ga -c "DISPLAY=:1 xdotool mousemove 960 540 click 1" 2>/dev/null || true
sleep 1

# Maximize window
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "GeoGebra" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    echo "Maximizing window $WID..."
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
else
    echo "WARNING: GeoGebra window not found via wmctrl."
fi

# 5. Capture initial state evidence
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="