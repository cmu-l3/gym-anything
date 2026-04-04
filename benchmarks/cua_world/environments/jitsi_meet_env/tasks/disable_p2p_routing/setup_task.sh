#!/bin/bash
set -e
echo "=== Setting up disable_p2p_routing task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Jitsi Meet is reachable
if ! wait_for_http "${JITSI_BASE_URL:-http://localhost:8080}" 120; then
    echo "ERROR: Jitsi Meet is not reachable"
    exit 1
fi

# 1. Clean state: Remove any existing custom config to ensure agent starts from scratch
CONFIG_FILE="/home/ga/.jitsi-meet-cfg/web/custom-config.js"
if [ -f "$CONFIG_FILE" ]; then
    echo "Removing existing custom config for clean start..."
    rm "$CONFIG_FILE"
fi

# 2. Clean state: Remove any previous evidence
rm -f "/home/ga/p2p_disabled_evidence.png"

# 3. Start Firefox at the home page
echo "Starting Firefox..."
restart_firefox "http://localhost:8080" 10
maximize_firefox
focus_firefox

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png
echo "Initial state captured."

echo "=== Task setup complete ==="