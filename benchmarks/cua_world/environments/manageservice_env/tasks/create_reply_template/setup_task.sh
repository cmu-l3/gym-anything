#!/bin/bash
# Setup for "create_reply_template" task

echo "=== Setting up Create Reply Template task ==="
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure SDP is running
ensure_sdp_running

# Clean up any existing template with this name to ensure fresh start
# 'replytemplate' is the standard table, but we try a safe delete
echo "Cleaning up old templates..."
sdp_db_exec "DELETE FROM replytemplate WHERE LOWER(templatename) = 'password reset completion';" 2>/dev/null || true

# Start Firefox on the Login page
ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/Login.do"
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "SDP is ready. Task: Create 'Password Reset Completion' reply template."