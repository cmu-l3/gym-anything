#!/bin/bash
# Setup script for Clock In Employee task
# Records initial state before the task begins
# CRITICAL: This script FAILS if prerequisites are not met

echo "=== Setting up Clock In Employee task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Run pre-flight check (BLOCKS until environment is ready)
if ! preflight_check; then
    echo "FATAL: Pre-flight check failed. Cannot start task."
    exit 1
fi

# Take initial screenshot
take_screenshot /tmp/task_initial_screenshot.png

# Record initial punch count
INITIAL_COUNT=$(get_punch_count)
echo "$INITIAL_COUNT" > /tmp/initial_punch_count
echo "Initial punch count: $INITIAL_COUNT"

# Record current timestamp for comparison
date +%s > /tmp/task_start_timestamp
echo "Task start timestamp: $(date)"

# CRITICAL: Verify that the expected employee exists in the database
# This MUST pass or the task cannot be completed
if ! verify_employee_exists "John" "Doe" "10"; then
    echo "FATAL: Required employee John Doe (Employee #10) not found in database!"
    echo "Cannot proceed with task. Demo data may not be initialized correctly."
    exit 1
fi

# Final verification - ensure we can see the login page
if ! verify_timetrex_accessible; then
    echo "FATAL: TimeTrex login page not accessible at task start!"
    exit 1
fi

echo ""
echo "=== Task Setup Complete - All Prerequisites Met ==="
echo "Task: Clock in employee John Doe (Employee #10) using the time clock feature"
echo "Navigate to Attendance > TimeSheet or Punch, select John Doe, and record a clock-in punch"
echo "Login credentials: demoadmin1 / demo"
echo ""
