#!/bin/bash
echo "=== Setting up Map CMDB Dependencies Task ==="

# Source task utilities for SDP specific functions
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# Record initial count of CIs to detect new creations
# We query baseelement which holds all CIs
INITIAL_CI_COUNT=$(sdp_db_exec "SELECT COUNT(*) FROM baseelement WHERE ciname IN ('Payroll Service', 'Payroll-DB-01');")
echo "${INITIAL_CI_COUNT:-0}" > /tmp/initial_ci_count.txt

echo "Initial matching CI count: ${INITIAL_CI_COUNT:-0}"

# Ensure ServiceDesk Plus is running and ready
ensure_sdp_running

# Open Firefox to the Home page or CMDB specific URL if known
# Using Home page to force navigation
ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/Home.do"

# Wait a moment for rendering
sleep 5

# Maximize Firefox
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="