#!/bin/bash
echo "=== Setting up bulk_update_sprint_review task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Ensure OpenProject is reachable
wait_for_openproject

# Launch Firefox directly to the target project's work package list
# This puts the agent in the correct context immediately
TARGET_URL="http://localhost:8080/projects/ecommerce-platform/work_packages"
echo "Launching Firefox to $TARGET_URL"
launch_firefox_to "$TARGET_URL" 8

# Maximize window to ensure UI elements are visible
maximize_firefox

# Capture initial screenshot for evidence
take_screenshot /tmp/task_initial.png

# Verify screenshot was captured
if [ -f /tmp/task_initial.png ]; then
    echo "Initial state captured successfully."
else
    echo "WARNING: Failed to capture initial state."
fi

echo "=== Task setup complete ==="