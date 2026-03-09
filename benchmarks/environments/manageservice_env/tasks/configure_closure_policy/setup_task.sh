#!/bin/bash
echo "=== Setting up Configure Closure Policy task ==="

# Source utilities for SDP
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure SDP is running (waits for install if needed)
ensure_sdp_running

# Wait for HTTPS to be ready
wait_for_sdp_https 600

# Ensure Firefox is open to the login page
ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/Login.do"

# Take initial screenshot
echo "Capturing initial state..."
sleep 5
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="