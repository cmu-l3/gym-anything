#!/bin/bash
set -e
echo "=== Setting up export_disaster_recovery_config task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure Nx Witness Server is ready and we have a token
refresh_nx_token > /dev/null 2>&1 || true

# Verify basic data existence (Agent relies on this data being present)
CAMERA_COUNT=$(count_cameras 2>/dev/null || echo "0")
USER_COUNT=$(count_users 2>/dev/null || echo "0")

echo "Current System State:"
echo "  Cameras: $CAMERA_COUNT"
echo "  Users: $USER_COUNT"

if [ "$CAMERA_COUNT" -lt "1" ]; then
    echo "WARNING: Low camera count. Task may be difficult."
fi

# Clean up any previous runs
rm -rf /home/ga/dr_export
rm -f /tmp/dr_ground_truth.json

# Open Firefox to the API documentation or Web Admin to give the agent a starting point
ensure_firefox_running "https://localhost:7001/static/index.html#/settings/system"
sleep 5
maximize_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="