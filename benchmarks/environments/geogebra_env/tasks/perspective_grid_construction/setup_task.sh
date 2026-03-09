#!/bin/bash
# Setup script for Perspective Grid Construction task
set -o pipefail

# Source utilities if available, otherwise define fallbacks
if [ -f "/workspace/scripts/task_utils.sh" ]; then
    source /workspace/scripts/task_utils.sh
else
    kill_geogebra() { pkill -u "${1:-ga}" -f "geogebra" 2>/dev/null || true; }
    launch_geogebra() { su - "${1:-ga}" -c "DISPLAY=:1 geogebra-classic > /tmp/geogebra.log 2>&1 &" 2>/dev/null || true; }
    focus_geogebra() { true; } # Placeholder
    maximize_geogebra() { true; } # Placeholder
fi

echo "=== Setting up Perspective Grid Task ==="

# 1. Clean environment
kill_geogebra ga
sleep 1

# 2. Prepare directories
mkdir -p /home/ga/Documents/GeoGebra/projects
chown -R ga:ga /home/ga/Documents/GeoGebra

# 3. Remove artifacts
rm -f /home/ga/Documents/GeoGebra/projects/perspective_grid.ggb 2>/dev/null || true

# 4. Record baseline state
find /home/ga/Documents/GeoGebra -name "*.ggb" 2>/dev/null | wc -l > /tmp/initial_ggb_count
date +%s > /tmp/task_start_time

# 5. Launch Application
echo "Launching GeoGebra..."
launch_geogebra ga

# Wait for load
for i in {1..45}; do
    if pgrep -f "geogebra" > /dev/null; then
        echo "GeoGebra process found."
        break
    fi
    sleep 1
done
sleep 10 # Allow GUI to render

# 6. Configure Window (Maximize/Focus)
# Attempt to find window ID
WID=$(DISPLAY=:1 wmctrl -l | grep -i "geogebra" | awk '{print $1}' | head -n 1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -a "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz
fi

# 7. Take initial evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="
echo "Instructions:"
echo "1. Draw Horizon Line at y=4"
echo "2. Place VP1 and VP2 on horizon"
echo "3. Construct 4x4 perspective grid using Diagonal Method for depth"
echo "4. Save to ~/Documents/GeoGebra/projects/perspective_grid.ggb"