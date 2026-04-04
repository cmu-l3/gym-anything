#!/bin/bash
set -e
echo "=== Setting up customize_compliance_links task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Jitsi Meet is reachable
if ! wait_for_http "${JITSI_BASE_URL:-http://localhost:8080}" 120; then
    echo "ERROR: Jitsi Meet is not reachable"
    exit 1
fi

# Clean any previous custom configuration to ensure a fresh start
rm -f /home/ga/.jitsi-meet-cfg/web/custom-interface_config.js

# Ensure the config directory exists
mkdir -p /home/ga/.jitsi-meet-cfg/web/
chown -R ga:ga /home/ga/.jitsi-meet-cfg/

# Open Firefox to the home page to show initial state (Invite button visible)
restart_firefox "http://localhost:8080" 10
maximize_firefox
focus_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="