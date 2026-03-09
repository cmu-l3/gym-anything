#!/bin/bash
set -e
echo "=== Setting up compare_fixed_vs_variable_aep task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# clean up previous artifacts
rm -f /home/ga/Documents/fixed_power_curve.txt
rm -f /home/ga/Documents/variable_power_curve.txt
rm -f /tmp/task_result.json

# Ensure sample projects exist (QBlade usually installs them)
SAMPLE_DIR="/home/ga/Documents/sample_projects"
if [ ! -d "$SAMPLE_DIR" ]; then
    mkdir -p "$SAMPLE_DIR"
    # Try to find them in installation
    INSTALL_SAMPLES=$(find /opt/qblade -name "sample projects" -type d 2>/dev/null | head -1)
    if [ -n "$INSTALL_SAMPLES" ]; then
        cp "$INSTALL_SAMPLES"/*.wpa "$SAMPLE_DIR/" 2>/dev/null || true
    fi
fi

# Ensure QBlade is running
launch_qblade

# Wait for window
wait_for_qblade 30

# Maximize window
DISPLAY=:1 wmctrl -r "QBlade" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "QBlade" 2>/dev/null || true

# Dismiss startup dialogs if any
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take screenshot of initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="