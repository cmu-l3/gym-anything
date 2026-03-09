#!/bin/bash
set -e
echo "=== Setting up evaluate_wake_interaction_two_turbines task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean up previous run artifacts
rm -f /home/ga/Documents/projects/wake_study.wpa
rm -f /home/ga/Documents/wake_loss_report.txt
rm -f /tmp/task_result.json

# Locate the sample project
SAMPLE_PROJECT_NAME="Turbine Simulation.wpa"
SAMPLE_PROJECT_PATH=""

# Search in standard locations
POSSIBLE_PATHS=(
    "/home/ga/Documents/sample_projects/$SAMPLE_PROJECT_NAME"
    "/opt/qblade/sample projects/$SAMPLE_PROJECT_NAME"
    "/opt/qblade/sample_projects/$SAMPLE_PROJECT_NAME"
    "/home/ga/Documents/sample_files/$SAMPLE_PROJECT_NAME"
)

for path in "${POSSIBLE_PATHS[@]}"; do
    if [ -f "$path" ]; then
        SAMPLE_PROJECT_PATH="$path"
        break
    fi
done

# If not found, look for any .wpa file to use as base
if [ -z "$SAMPLE_PROJECT_PATH" ]; then
    SAMPLE_PROJECT_PATH=$(find /home/ga/Documents/sample_projects -name "*.wpa" | head -n 1)
fi

echo "Using sample project: $SAMPLE_PROJECT_PATH"

# Prepare directory structure
mkdir -p /home/ga/Documents/projects
chown ga:ga /home/ga/Documents/projects

# Launch QBlade
# If we found a sample project, load it on launch
if [ -n "$SAMPLE_PROJECT_PATH" ]; then
    echo "Launching QBlade with project..."
    launch_qblade "$SAMPLE_PROJECT_PATH"
else
    echo "Launching QBlade (no sample found, user must locate)..."
    launch_qblade
fi

# Wait for QBlade to start
echo "Waiting for QBlade to initialize..."
wait_for_qblade 30

# Maximize the window
DISPLAY=:1 wmctrl -r "QBlade" -b add,maximized_vert,maximized_horz 2>/dev/null || true
# Fallback focus
DISPLAY=:1 wmctrl -a "QBlade" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="