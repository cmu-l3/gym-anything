#!/bin/bash
echo "=== Setting up organize_project_layer_groups task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure data directories exist and have correct permissions
mkdir -p /home/ga/gvsig_data/projects
chown -R ga:ga /home/ga/gvsig_data

# Clean up any previous run artifacts
TARGET_PROJECT="/home/ga/gvsig_data/projects/organized_basemap.gvsproj"
if [ -f "$TARGET_PROJECT" ]; then
    echo "Removing previous project file: $TARGET_PROJECT"
    rm -f "$TARGET_PROJECT"
fi

# Kill any running gvSIG instances to ensure a fresh start
kill_gvsig

# Launch gvSIG with an empty session
echo "Launching gvSIG..."
# Launching without arguments starts an empty project manager
launch_gvsig ""

# Verify the window appeared
if ! wait_for_window "gvSIG" 60; then
    echo "WARNING: gvSIG window did not appear in time"
fi

# Take initial screenshot for evidence
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="