#!/bin/bash
set -e
echo "=== Setting up Jitsi Focus Mode task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Jitsi is running
if ! docker ps | grep -q jitsi-web; then
    echo "Starting Jitsi containers..."
    cd /home/ga/jitsi
    docker compose up -d
    wait_for_http "http://localhost:8080" 120
fi

# 1. Clean state: Remove any existing custom config
CONFIG_DIR="/home/ga/.jitsi-meet-cfg/web"
CUSTOM_CONFIG="$CONFIG_DIR/custom-interface_config.js"

if [ -f "$CUSTOM_CONFIG" ]; then
    echo "Removing existing custom config..."
    rm -f "$CUSTOM_CONFIG"
fi

# Ensure Documents directory exists for screenshots
mkdir -p /home/ga/Documents

# 2. Reset Firefox to clean state
stop_firefox
rm -f /home/ga/Documents/focus_mode_toolbar.png
rm -f /home/ga/Documents/focus_mode_branding.png

# 3. Open Firefox at default Jitsi to show "Before" state
echo "Launching Firefox..."
restart_firefox "http://localhost:8080" 10
maximize_firefox
focus_firefox

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="