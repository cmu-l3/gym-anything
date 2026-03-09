#!/bin/bash
set -e

echo "=== Setting up customize_branding task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Ensure Jitsi Meet is running initially
if ! wait_for_http "${JITSI_BASE_URL:-http://localhost:8080}" 120; then
    echo "ERROR: Jitsi Meet is not reachable at start"
    # Try to start it if not running
    cd /home/ga/jitsi
    docker compose up -d
    wait_for_http "${JITSI_BASE_URL:-http://localhost:8080}" 120
fi

# Clean up any existing custom configurations to ensure a fresh start
CONFIG_DIR="/home/ga/.jitsi-meet-cfg/web"
rm -f "$CONFIG_DIR/custom-interface_config.js"
rm -f "$CONFIG_DIR/custom-config.js"

# Create Documents directory for agent output
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents
rm -f /home/ga/Documents/branding_verification.png
rm -f /home/ga/Documents/branding_report.txt

# Start Firefox at the default Jitsi home page
restart_firefox "http://localhost:8080" 10
maximize_firefox
focus_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== customize_branding setup complete ==="