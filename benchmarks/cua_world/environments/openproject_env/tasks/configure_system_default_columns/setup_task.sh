#!/bin/bash
# Setup script for configure_system_default_columns task

source /workspace/scripts/task_utils.sh

echo "=== Setting up configure_system_default_columns task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Wait for OpenProject to be ready
wait_for_openproject

# Record initial state of the setting (for debugging/verification context)
echo "Recording initial settings state..."
op_rails "puts Setting.work_package_list_default_columns.to_json" > /tmp/initial_columns.json 2>/dev/null || echo "[]" > /tmp/initial_columns.json

# Launch Firefox to the login page
# We send them to login because we can't easily pre-seed the session cookies
launch_firefox_to "http://localhost:8080/login" 5

# Maximize for best visibility
maximize_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="