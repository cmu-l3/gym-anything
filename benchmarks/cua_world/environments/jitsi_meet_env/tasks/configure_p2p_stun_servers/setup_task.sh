#!/bin/bash
set -e
echo "=== Setting up Configure STUN Servers task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Jitsi is up and running
echo "Checking Jitsi Meet availability..."
if ! wait_for_http "${JITSI_BASE_URL:-http://localhost:8080}" 120; then
    echo "ERROR: Jitsi Meet is not reachable"
    exit 1
fi

# Ensure the config file exists where expected
CONFIG_PATH="/home/ga/.jitsi-meet-cfg/web/config.js"
if [ ! -f "$CONFIG_PATH" ]; then
    echo "ERROR: Config file not found at $CONFIG_PATH"
    exit 1
fi

# Create a backup of the config file (hidden from agent, or just for restoration)
cp "$CONFIG_PATH" "/tmp/config.js.bak"

# Record initial file timestamp
stat -c %Y "$CONFIG_PATH" > /tmp/initial_config_mtime.txt

# Start Firefox and navigate to the config file (to show agent where it is hosted)
echo "Starting Firefox..."
restart_firefox "${JITSI_BASE_URL:-http://localhost:8080}/config.js" 10
maximize_firefox
focus_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Config file location: $CONFIG_PATH"
echo "Task: Add Google STUN servers to p2p.stunServers list and restart service."