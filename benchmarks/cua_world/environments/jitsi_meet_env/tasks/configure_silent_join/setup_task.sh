#!/bin/bash
set -e
echo "=== Setting up configure_silent_join task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Jitsi Meet is running initially
if ! wait_for_http "http://localhost:8080" 120; then
    echo "Starting Jitsi Meet..."
    cd /home/ga/jitsi
    docker compose up -d
    wait_for_http "http://localhost:8080" 300
fi

# Clean up any previous attempt artifacts
rm -f /home/ga/.jitsi-meet-cfg/web/custom-config.js
rm -f /home/ga/silent_join_result.txt

# Create empty custom config file with correct permissions to ensure agent can edit it
# (The directory is root-owned by Docker setup usually, but mapped to ga user in some setups. 
# We ensure ga can write to this specific file location.)
mkdir -p /home/ga/.jitsi-meet-cfg/web
touch /home/ga/.jitsi-meet-cfg/web/custom-config.js
chown ga:ga /home/ga/.jitsi-meet-cfg/web/custom-config.js
chmod 644 /home/ga/.jitsi-meet-cfg/web/custom-config.js

# Start Firefox at home page
restart_firefox "http://localhost:8080" 10
maximize_firefox
focus_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="