#!/bin/bash
echo "=== Setting up pitch_sweep_characteristic task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists and is empty of target file
mkdir -p /home/ga/Documents/projects
rm -f /home/ga/Documents/projects/pitch_sweep_result.wpa 2>/dev/null || true

# Find a suitable sample project to load
# QBlade sample projects are usually located in Documents/sample_projects after install
SAMPLE_PROJECT=""
SAMPLE_DIR="/home/ga/Documents/sample_projects"

if [ -d "$SAMPLE_DIR" ]; then
    # Prefer the NREL 5MW reference if available, as it's a standard test case
    if [ -f "$SAMPLE_DIR/NREL_5MW_Reference.wpa" ]; then
        SAMPLE_PROJECT="$SAMPLE_DIR/NREL_5MW_Reference.wpa"
    else
        # Otherwise take the first .wpa file found
        SAMPLE_PROJECT=$(find "$SAMPLE_DIR" -name "*.wpa" | head -n 1)
    fi
fi

# Record the size of the input project for comparison later
# (Result file should be larger due to simulation data)
if [ -n "$SAMPLE_PROJECT" ] && [ -f "$SAMPLE_PROJECT" ]; then
    stat -c%s "$SAMPLE_PROJECT" > /tmp/input_project_size.txt
    echo "Selected sample project: $SAMPLE_PROJECT"
else
    echo "WARNING: No sample project found. Agent will start with empty QBlade."
    echo "0" > /tmp/input_project_size.txt
fi

# Launch QBlade with the sample project
echo "Launching QBlade..."
if [ -n "$SAMPLE_PROJECT" ]; then
    launch_qblade "$SAMPLE_PROJECT"
else
    launch_qblade
fi

# Wait for QBlade window to appear
wait_for_qblade 30

# Maximize the window (important for VLM visibility)
DISPLAY=:1 wmctrl -r "QBlade" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="