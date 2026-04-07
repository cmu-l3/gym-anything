#!/bin/bash
# Setup script for IP Punch Restriction task
# Records initial state before the task begins
# CRITICAL: This script FAILS if prerequisites are not met

echo "=== Setting up Configure IP Punch Restriction task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Run pre-flight check (BLOCKS until environment is ready)
if ! preflight_check; then
    echo "FATAL: Pre-flight check failed. Cannot start task."
    exit 1
fi

# Take initial screenshot
take_screenshot /tmp/task_initial_screenshot.png

# Record initial station count (Anti-gaming)
INITIAL_COUNT=$(timetrex_query "SELECT COUNT(*) FROM station WHERE deleted=0" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_station_count
echo "Initial station count: $INITIAL_COUNT"

# Record task start timestamp in epoch seconds (Anti-gaming)
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/task_start_timestamp
echo "Task start timestamp: $TASK_START"

# Clean up any stations that might perfectly match our target (to prevent false positives from previous runs)
docker exec timetrex-postgres psql -U timetrex -d timetrex -c "UPDATE station SET deleted=1 WHERE source LIKE '%204.174.1.100%' OR source LIKE '%204.174.1.105%';" >/dev/null 2>&1 || true

# Final verification - ensure we can see the login page
if ! verify_timetrex_accessible; then
    echo "FATAL: TimeTrex login page not accessible at task start!"
    exit 1
fi

echo ""
echo "=== Task Setup Complete ==="
echo "Task: Create two new Station records for IP restriction"
echo "Login credentials: demoadmin1 / demo"
echo ""