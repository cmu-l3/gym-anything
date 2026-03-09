#!/bin/bash
set -e
echo "=== Setting up Configure Change Risk task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure ServiceDesk Plus is running and ready
ensure_sdp_running

# Open Firefox to the login page
# The agent needs to log in, so we just provide the login page
ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/Login.do"

# Wait for window to stabilize
sleep 5

# Maximize Firefox
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="
echo "Credentials: administrator / administrator"
echo "Target: Admin > Change Management > Risk"