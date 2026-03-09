#!/bin/bash
set -e
echo "=== Setting up configure_patient_interface task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Jitsi is reachable
if ! wait_for_http "http://localhost:8080" 120; then
    echo "ERROR: Jitsi Meet is not reachable"
    exit 1
fi

# Reset interface_config.js to default state if possible
# We do this by restarting the container which usually regenerates config or checking if we can overwrite it
# For this task, we'll assume a clean state or just let the agent overwrite whatever is there.
# To be safe against previous runs, we can try to restore a backup if it exists, or just proceed.
# (In a fresh env, this isn't strictly necessary, but good practice)

# Find web container
WEB_CONTAINER=$(docker ps --format "{{.Names}}" | grep -i "web" | head -n 1)
if [ -z "$WEB_CONTAINER" ]; then
    echo "ERROR: Could not find Jitsi web container"
    exit 1
fi
echo "Found web container: $WEB_CONTAINER"

# Start Firefox at home page
restart_firefox "http://localhost:8080" 10
maximize_firefox
focus_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="