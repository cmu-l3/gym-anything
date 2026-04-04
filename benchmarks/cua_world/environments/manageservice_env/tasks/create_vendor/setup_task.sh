#!/bin/bash
echo "=== Setting up Create Vendor Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure ServiceDesk Plus is running
# This handles the wait for installation and startup
ensure_sdp_running

# 2. Clean State: Remove vendor if it already exists (to prevent false positives)
# We delete from VendorDefinition table (or similar) based on name
echo "Ensuring clean state (deleting existing vendor if present)..."
sdp_db_exec "DELETE FROM vendordefinition WHERE LOWER(vendorname) LIKE '%proav distribution%';" 2>/dev/null || true
# Also try 'vendor' table just in case schema differs in this version
sdp_db_exec "DELETE FROM vendor WHERE LOWER(vendorname) LIKE '%proav distribution%';" 2>/dev/null || true

# 3. Launch Firefox to the Login page
echo "Launching Firefox..."
ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/Login.do"

# 4. Wait a moment for UI to stabilize
sleep 5

# 5. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="