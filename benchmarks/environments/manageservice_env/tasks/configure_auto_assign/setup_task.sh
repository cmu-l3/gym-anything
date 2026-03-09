#!/bin/bash
set -e
echo "=== Setting up configure_auto_assign task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Wait for SDP to be fully running
ensure_sdp_running

# 2. Clear mandatory password change (allows easy login)
clear_mandatory_password_change

# 3. RESET STATE: Ensure Auto Assign is DISABLED and Administrator is NOT excluded
echo "Resetting Auto Assign configuration..."

# Disable Auto Assign
# We use a broad update in case the param exists
sdp_db_exec "UPDATE GlobalConfig SET param_value='false' WHERE param_name='AUTO_ASSIGN_STATUS';" 2>/dev/null || true

# Remove Administrator from exclusion list (TechAutoAssignExclude table)
# We find the admin ID first to be safe
ADMIN_ID=$(sdp_db_exec "SELECT account_id FROM aaaaccount a JOIN aaalogin l ON l.login_id = a.login_id WHERE LOWER(l.name) = 'administrator';" 2>/dev/null | head -n 1)

if [ -n "$ADMIN_ID" ]; then
    echo "Admin ID found: $ADMIN_ID. Clearing exclusions..."
    sdp_db_exec "DELETE FROM TechAutoAssignExclude WHERE technician_id = $ADMIN_ID;" 2>/dev/null || true
fi

# 4. Record Initial State for verification comparison
INITIAL_STATUS=$(sdp_db_exec "SELECT param_value FROM GlobalConfig WHERE param_name='AUTO_ASSIGN_STATUS';" 2>/dev/null || echo "false")
echo "$INITIAL_STATUS" > /tmp/initial_auto_assign_status.txt

# 5. Launch Firefox to the Admin Login
log "Launching Firefox..."
ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/Login.do"

# 6. Capture initial screenshot
echo "Capturing initial state..."
sleep 5
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="