#!/bin/bash
# Setup for "configure_attachment_security" task
# Ensures SDP is running and opens Firefox to the login page.

set -e
echo "=== Setting up Configure Attachment Security task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure ServiceDesk Plus is running (handles install/start)
echo "Ensuring SDP service is up..."
ensure_sdp_running

# 2. Clear password change requirement for smoother agent interaction
clear_mandatory_password_change

# 3. Snapshot initial configuration (to detect changes)
# We dump GlobalConfig security params to see what was there before
echo "Recording initial security configuration..."
sdp_db_exec "SELECT paramname, paramvalue FROM globalconfig WHERE category LIKE '%Security%' OR paramname LIKE '%Attachment%' OR paramname LIKE '%Extension%';" > /tmp/initial_config_dump.txt 2>/dev/null || true

# 4. Launch Firefox to SDP Login
echo "Launching Firefox..."
ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/Login.do"
sleep 5

# 5. Capture initial state screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "Task: Block 'exe', 'bat', 'cmd', 'vbs', 'sh' file attachments in Admin > Security Settings."