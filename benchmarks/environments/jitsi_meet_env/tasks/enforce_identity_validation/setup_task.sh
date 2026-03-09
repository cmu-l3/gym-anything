#!/bin/bash
set -e

echo "=== Setting up enforce_identity_validation task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Reset configuration to default state (remove custom config if exists)
CONFIG_FILE="/home/ga/.jitsi-meet-cfg/web/custom-config.js"
if [ -f "$CONFIG_FILE" ]; then
    echo "Resetting custom config..."
    rm "$CONFIG_FILE"
fi

# Ensure Documents directory exists for evidence
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Remove old evidence files if they exist
rm -f /home/ga/Documents/evidence_blocked.png
rm -f /home/ga/Documents/evidence_success.png

# Ensure Jitsi is running healthy to start
if ! wait_for_http "${JITSI_BASE_URL:-http://localhost:8080}" 120; then
    echo "ERROR: Jitsi Meet is not reachable"
    # Try to restart
    cd /home/ga/jitsi
    docker compose up -d
    wait_for_http "${JITSI_BASE_URL:-http://localhost:8080}" 120
fi

# Close Firefox if open
stop_firefox

# Open Firefox to the Jitsi home page to start
restart_firefox "http://localhost:8080" 10
maximize_firefox
focus_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="