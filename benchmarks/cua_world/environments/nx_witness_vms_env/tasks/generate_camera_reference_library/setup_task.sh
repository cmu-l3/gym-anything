#!/bin/bash
set -e
echo "=== Setting up generate_camera_reference_library task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Ensure clean state: remove output directory if it exists
rm -rf /home/ga/Documents/ReferenceImages

# Refresh auth token so API is ready to accept connections if agent checks immediately
refresh_nx_token > /dev/null

# Verify cameras are actually initialized (task is impossible without cameras)
echo "Checking camera availability..."
CAMERA_COUNT=$(count_cameras)
if [ "$CAMERA_COUNT" -eq "0" ]; then
    echo "Waiting for cameras to register..."
    sleep 10
    CAMERA_COUNT=$(count_cameras)
fi
echo "System has $CAMERA_COUNT cameras active."

# Ensure Firefox is running (standard environment state)
ensure_firefox_running "https://localhost:7001/static/index.html"
maximize_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="