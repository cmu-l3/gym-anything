#!/bin/bash
set -e
echo "=== Setting up Configure Kiosk Toolbar task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Jitsi is running
if ! wait_for_http "${JITSI_BASE_URL:-http://localhost:8080}" 60; then
    echo "Starting Jitsi..."
    cd /home/ga/jitsi
    docker compose up -d
    wait_for_http "${JITSI_BASE_URL:-http://localhost:8080}" 120
fi

# Ensure the config directory exists
mkdir -p /home/ga/.jitsi-meet-cfg/web/

# Backup any existing config (start fresh-ish)
if [ -f /home/ga/.jitsi-meet-cfg/web/custom-config.js ]; then
    mv /home/ga/.jitsi-meet-cfg/web/custom-config.js /home/ga/.jitsi-meet-cfg/web/custom-config.js.bak
fi

# Create an empty or comment-only custom config to start
echo "// Jitsi Meet Custom Configuration" > /home/ga/.jitsi-meet-cfg/web/custom-config.js
chown ga:ga /home/ga/.jitsi-meet-cfg/web/custom-config.js

# Launch Firefox to show initial state (full toolbar)
# We navigate to a specific room so the toolbar is visible in the initial screenshot
echo "Launching Firefox..."
ROOM_URL="http://localhost:8080/InitialCheck"

# Use utility to start firefox
restart_firefox "$ROOM_URL" 10
maximize_firefox
focus_firefox

# Join meeting to show the full toolbar
join_meeting 8

# Take initial screenshot showing the standard full toolbar
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="