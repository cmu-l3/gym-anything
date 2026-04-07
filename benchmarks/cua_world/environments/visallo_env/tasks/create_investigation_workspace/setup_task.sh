#!/bin/bash
echo "=== Setting up create_investigation_workspace task ==="

source /workspace/scripts/task_utils.sh

# Ensure Visallo is ready
if ! ensure_visallo_ready 30; then
    echo "CRITICAL ERROR: Visallo is not accessible."
    exit 1
fi

date +%s > /tmp/task_start_time

# Restart Firefox at Visallo login page
restart_firefox "$VISALLO_URL/"
sleep 2

take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "Agent should see the Visallo login page in Firefox"
