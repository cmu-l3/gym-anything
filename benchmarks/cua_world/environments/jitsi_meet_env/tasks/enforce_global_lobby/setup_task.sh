#!/bin/bash
set -e

echo "=== Setting up enforce_global_lobby task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming (container restart check)
date +%s > /tmp/task_start_time.txt

# Ensure Jitsi Meet is reachable
if ! wait_for_http "${JITSI_BASE_URL:-http://localhost:8080}" 120; then
    echo "ERROR: Jitsi Meet is not reachable"
    exit 1
fi

# Ensure config file exists
CONFIG_FILE="/home/ga/.jitsi-meet-cfg/web/config.js"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Config file not found at $CONFIG_FILE"
    # Attempt to regenerate it or fail
    exit 1
fi

# Reset state: Ensure autoEnable is NOT true to start with
# We look for "autoEnable: true" and replace with "autoEnable: false"
sed -i 's/autoEnable: true/autoEnable: false/g' "$CONFIG_FILE"

# Start Firefox at Jitsi home page
restart_firefox "http://localhost:8080" 8
maximize_firefox
focus_firefox

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "Task start screenshot saved to /tmp/task_start.png"
echo "=== Setup complete ==="