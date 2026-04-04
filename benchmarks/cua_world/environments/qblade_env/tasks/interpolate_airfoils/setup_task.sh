#!/bin/bash
echo "=== Setting up interpolate_airfoils task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists and is clean
mkdir -p /home/ga/Documents/airfoils
chown ga:ga /home/ga/Documents/airfoils

# Remove target file if it exists to prevent false positives
rm -f /home/ga/Documents/airfoils/interpolated_naca_50pct.dat 2>/dev/null || true

# Launch QBlade
echo "Launching QBlade..."
launch_qblade

# Wait for QBlade window
wait_for_qblade 30

# Maximize window for better visibility
QBLADE_WID=$(DISPLAY=:1 wmctrl -l | grep -i "qblade" | cut -d' ' -f1 | head -1)
if [ -n "$QBLADE_WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$QBLADE_WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    # Focus
    DISPLAY=:1 wmctrl -i -a "$QBLADE_WID" 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="