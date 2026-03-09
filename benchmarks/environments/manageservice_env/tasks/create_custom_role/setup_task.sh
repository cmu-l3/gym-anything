#!/bin/bash
# Setup for "create_custom_role" task
# Ensures SDP is running, captures initial DB state, and opens browser

echo "=== Setting up Create Custom Role task ==="
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# 1. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Ensure ServiceDesk Plus is running (waits for install if needed)
ensure_sdp_running

# 3. Capture initial role count to detect creation of new records
# Queries the AaaRole table (standard ManageEngine auth schema)
echo "Recording initial role count..."
INITIAL_ROLES=$(sdp_db_exec "SELECT COUNT(*) FROM AaaRole;" 2>/dev/null || echo "0")
echo "$INITIAL_ROLES" > /tmp/initial_role_count.txt
log "Initial roles: $INITIAL_ROLES"

# 4. Ensure no conflicting role exists from previous runs
sdp_db_exec "DELETE FROM AaaRole WHERE name = 'L1 Support Analyst';" 2>/dev/null || true

# 5. Launch Firefox to the Login page
ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/Login.do"

# 6. Capture initial state screenshot
sleep 5
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="
echo "SDP URL: $SDP_BASE_URL"
echo "Target: Create role 'L1 Support Analyst'"