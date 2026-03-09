#!/bin/bash
set -e
echo "=== Setting up Disable Shared Video task ==="

source /workspace/scripts/task_utils.sh

# 1. Record start time
date +%s > /tmp/task_start_time.txt

# 2. Ensure Jitsi is reachable
if ! wait_for_http "http://localhost:8080" 60; then
    echo "ERROR: Jitsi Meet not reachable. Attempting to start..."
    cd /home/ga/jitsi && docker compose up -d
    wait_for_http "http://localhost:8080" 120
fi

# 3. Ensure 'sharedvideo' is ENABLED in the config to start with
# The config is mounted at /home/ga/.jitsi-meet-cfg/web/config.js
CONFIG_HOST_PATH="/home/ga/.jitsi-meet-cfg/web/config.js"

if [ -f "$CONFIG_HOST_PATH" ]; then
    echo "Checking initial config state..."
    # Check if toolbarButtons exists
    if grep -q "toolbarButtons" "$CONFIG_HOST_PATH"; then
        # Check if sharedvideo is missing
        if ! grep -q "'sharedvideo'" "$CONFIG_HOST_PATH" && ! grep -q "\"sharedvideo\"" "$CONFIG_HOST_PATH"; then
            echo "Enabling sharedvideo for initial state..."
            # Naive insertion: find 'microphone' and add 'sharedvideo' after it
            sed -i "s/'microphone'/'microphone', 'sharedvideo'/g" "$CONFIG_HOST_PATH"
        fi
    else
        echo "WARNING: toolbarButtons array not found in config. Assuming default implicit state."
    fi
else
    echo "WARNING: Config file not found on host at $CONFIG_HOST_PATH"
fi

# 4. Start Firefox and join a meeting to show the button exists
echo "Starting Firefox..."
restart_firefox "http://localhost:8080/TestRoom" 8
maximize_firefox
focus_firefox

# Join meeting so the toolbar is accessible
join_meeting 10

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="