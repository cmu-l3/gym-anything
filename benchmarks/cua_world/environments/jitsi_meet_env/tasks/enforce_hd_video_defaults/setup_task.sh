#!/bin/bash
set -e
echo "=== Setting up enforce_hd_video_defaults task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Jitsi is reachable initially
if ! wait_for_http "${JITSI_BASE_URL:-http://localhost:8080}" 120; then
    echo "ERROR: Jitsi Meet is not reachable"
    exit 1
fi

# Clean up any previous run artifacts
rm -f /home/ga/served_config.js
# Note: We don't reset the config file itself to strict defaults because 
# the environment starts fresh or we want to simulate a persistent machine. 
# However, ensuring a known state is good. 
# For this task, we assume the initial state is the default (adaptive/360p).

# Start Firefox at the home page
restart_firefox "http://localhost:8080" 10
maximize_firefox
focus_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="