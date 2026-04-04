#!/bin/bash
echo "=== Setting up design_swept_blade task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
mkdir -p /home/ga/Documents/projects
chown ga:ga /home/ga/Documents/projects

# Cleanup previous run artifacts
rm -f /home/ga/Documents/projects/swept_blade.wpa 2>/dev/null || true
rm -f /home/ga/Documents/projects/swept_blade.stl 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# Ensure sample projects are available (crucial for starting the task)
SAMPLE_DIR=$(find /opt/qblade -name "sample projects" -type d 2>/dev/null | head -1)
if [ -z "$SAMPLE_DIR" ]; then
    SAMPLE_DIR=$(find /opt/qblade -iname "sampleprojects" -type d 2>/dev/null | head -1)
fi

# If internal samples missing/hard to find, copy fallback if available
# (The environment script usually copies them to ~/Documents/sample_projects/)
if [ ! -d "/home/ga/Documents/sample_projects" ] || [ -z "$(ls -A /home/ga/Documents/sample_projects)" ]; then
    echo "WARNING: Sample projects not found in Documents. Attempting to restore..."
    mkdir -p /home/ga/Documents/sample_projects
    if [ -n "$SAMPLE_DIR" ]; then
        cp "$SAMPLE_DIR"/* /home/ga/Documents/sample_projects/ 2>/dev/null || true
    fi
    chown -R ga:ga /home/ga/Documents/sample_projects
fi

# Launch QBlade
echo "Launching QBlade..."
launch_qblade

# Wait for window
wait_for_qblade 30

# Maximize window
DISPLAY=:1 wmctrl -r "QBlade" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="