#!/bin/bash
# Setup script for Add Absence Request task
# Records initial state before the task begins
# CRITICAL: This script FAILS if prerequisites are not met

echo "=== Setting up Add Absence Request task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Run pre-flight check (BLOCKS until environment is ready)
if ! preflight_check; then
    echo "FATAL: Pre-flight check failed. Cannot start task."
    exit 1
fi

# Take initial screenshot
take_screenshot /tmp/task_initial_screenshot.png

# Record initial request/absence count
# TimeTrex stores absence requests in the request table
INITIAL_COUNT=$(timetrex_query "SELECT COUNT(*) FROM request" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_request_count
echo "Initial request count: $INITIAL_COUNT"

# CRITICAL: Verify that the expected employee exists in the database
# This MUST pass or the task cannot be completed
if ! verify_employee_exists "Heather" "Grant" "24"; then
    echo "FATAL: Required employee Heather Grant (Employee #24) not found in database!"
    echo "Cannot proceed with task. Demo data may not be initialized correctly."
    exit 1
fi

# Calculate a valid date within the next 7 days for explicit guidance
VALID_DATE=$(python3 -c "
from datetime import datetime, timedelta
import random
today = datetime.now()
# Pick a random day between tomorrow and 7 days from now
days_ahead = random.randint(1, 7)
target_day = today + timedelta(days=days_ahead)
print(target_day.strftime('%Y-%m-%d (%A)'))
" 2>/dev/null || echo "a date within the next 7 days")
echo "Suggested absence date: $VALID_DATE"

# Final verification - ensure we can see the login page
if ! verify_timetrex_accessible; then
    echo "FATAL: TimeTrex login page not accessible at task start!"
    exit 1
fi

echo ""
echo "=== Task Setup Complete - All Prerequisites Met ==="
echo "Task: Submit a vacation absence request for Heather Grant (Employee #24)"
echo "Navigate to Attendance > Requests, select Heather Grant"
echo "Create a SINGLE DAY vacation request for $VALID_DATE"
echo "The absence type should be 'Vacation'"
echo "Login credentials: demoadmin1 / demo"
echo ""
