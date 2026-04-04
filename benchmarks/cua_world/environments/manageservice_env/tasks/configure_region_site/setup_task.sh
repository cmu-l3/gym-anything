#!/bin/bash
echo "=== Setting up Configure Region and Site task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure ServiceDesk Plus is running
echo "Waiting for ServiceDesk Plus..."
ensure_sdp_running

# Clean up any previous attempts (Idempotency)
echo "Cleaning up stale data..."
sdp_db_exec "DELETE FROM sitedefinition WHERE sitename = 'Singapore Hub';"
sdp_db_exec "DELETE FROM regiondefinition WHERE regionname = 'Asia Pacific';"

# Record initial state (should be 0)
REGION_COUNT=$(sdp_db_exec "SELECT COUNT(*) FROM regiondefinition WHERE regionname = 'Asia Pacific';" 2>/dev/null || echo "0")
SITE_COUNT=$(sdp_db_exec "SELECT COUNT(*) FROM sitedefinition WHERE sitename = 'Singapore Hub';" 2>/dev/null || echo "0")
echo "$REGION_COUNT" > /tmp/initial_region_count
echo "$SITE_COUNT" > /tmp/initial_site_count

# Launch Firefox to the Admin Login page or Home
echo "Launching Firefox..."
ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/Login.do"
sleep 8

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="