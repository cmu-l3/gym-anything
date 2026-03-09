#!/bin/bash
# Setup script for Create Schedule task
# Records initial state before the task begins
# CRITICAL: This script FAILS if prerequisites are not met

echo "=== Setting up Create Schedule task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Run pre-flight check (BLOCKS until environment is ready)
if ! preflight_check; then
    echo "FATAL: Pre-flight check failed. Cannot start task."
    exit 1
fi

# Take initial screenshot
take_screenshot /tmp/task_initial_screenshot.png

# Record initial schedule count
INITIAL_COUNT=$(get_schedule_count)
echo "$INITIAL_COUNT" > /tmp/initial_schedule_count
echo "Initial schedule count: $INITIAL_COUNT"

# CRITICAL: Verify that the expected employee exists in the database
# This MUST pass or the task cannot be completed
if ! verify_employee_exists "Jane" "Doe" "20"; then
    echo "FATAL: Required employee Jane Doe (Employee #20) not found in database!"
    echo "Cannot proceed with task. Demo data may not be initialized correctly."
    exit 1
fi

# Calculate the next weekday for explicit date guidance
NEXT_WEEKDAY=$(python3 -c "
from datetime import datetime, timedelta
today = datetime.now()
days_ahead = 1
while True:
    next_day = today + timedelta(days=days_ahead)
    if next_day.weekday() < 5:  # Monday=0 through Friday=4
        print(next_day.strftime('%Y-%m-%d (%A)'))
        break
    days_ahead += 1
" 2>/dev/null || echo "the next weekday")
echo "Suggested schedule date: $NEXT_WEEKDAY"

# Final verification - ensure we can see the login page
if ! verify_timetrex_accessible; then
    echo "FATAL: TimeTrex login page not accessible at task start!"
    exit 1
fi

echo ""
echo "=== Task Setup Complete - All Prerequisites Met ==="
echo "Task: Create a work schedule for Jane Doe (Employee #20)"
echo "Navigate to Attendance > Schedules, select Jane Doe"
echo "Create a shift for $NEXT_WEEKDAY from 9:00 AM to 5:00 PM (09:00-17:00)"
echo "Login credentials: demoadmin1 / demo"
echo ""
