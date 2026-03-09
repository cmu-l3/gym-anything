#!/bin/bash
set -e
echo "=== Setting up task: add_clinic_facility ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for LibreHealth EHR to be accessible
wait_for_librehealth 120

# Clean state: Remove the facility if it exists from previous runs
echo "Cleaning up pre-existing test facility..."
librehealth_query "DELETE FROM facility WHERE name LIKE '%Lakewood Family Health%'" 2>/dev/null || true

# Record initial facility count (for anti-gaming)
INITIAL_FACILITY_COUNT=$(librehealth_query "SELECT COUNT(*) FROM facility" 2>/dev/null || echo "0")
echo "$INITIAL_FACILITY_COUNT" > /tmp/initial_facility_count.txt
echo "Initial facility count: $INITIAL_FACILITY_COUNT"

# Restart Firefox at the login page
restart_firefox "http://localhost:8000/interface/login/login.php?site=default"
sleep 3

# Take screenshot of initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="