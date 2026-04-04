#!/bin/bash
echo "=== Setting up Create Task Template task ==="

# Source shared utilities for SDP interaction
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 1. Ensure ServiceDesk Plus is running
ensure_sdp_running

# 2. Clean up any previous artifacts (Idempotency)
# We remove any existing task template with this name so the agent must create it fresh
log "Cleaning up old templates..."
sdp_db_exec "DELETE FROM tasktemplate WHERE title ILIKE '%Server Patching Protocol%';" || true

# 3. Launch Firefox to the Login page
# We use the utility to ensure it waits for the window
ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/Login.do"

# 4. Capture initial state screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="