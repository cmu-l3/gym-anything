#!/bin/bash
set -e
echo "=== Setting up analyze_spanwise_loads task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure clean state for output files
rm -f /home/ga/Documents/spanwise_loads.txt 2>/dev/null || true
rm -f /home/ga/Documents/max_load_report.txt 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# Ensure sample project exists in the accessible location
SAMPLE_PROJ_SRC="/opt/qblade/sample_projects/Turbine Simulation.wpa"
SAMPLE_PROJ_DEST="/home/ga/Documents/sample_projects/Turbine Simulation.wpa"

# If not in default opt location, check the standard install paths or the pre-copied docs
if [ ! -f "$SAMPLE_PROJ_DEST" ]; then
    echo "Restoring sample project..."
    # Try to find it in opt if not in Documents
    FOUND_SRC=$(find /opt/qblade -name "Turbine Simulation.wpa" 2>/dev/null | head -1)
    if [ -n "$FOUND_SRC" ]; then
        cp "$FOUND_SRC" "$SAMPLE_PROJ_DEST"
        chown ga:ga "$SAMPLE_PROJ_DEST"
    fi
fi

if [ ! -f "$SAMPLE_PROJ_DEST" ]; then
    echo "WARNING: Sample project 'Turbine Simulation.wpa' not found. Agent may need to find it."
else
    echo "Sample project verified at: $SAMPLE_PROJ_DEST"
fi

# Launch QBlade
echo "Launching QBlade..."
launch_qblade

# Wait for QBlade to start and window to appear
wait_for_qblade 30

# Maximize window
DISPLAY=:1 wmctrl -r "QBlade" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="