#!/bin/bash
# Setup script for Create Payroll Pay Codes task

echo "=== Setting up Create Payroll Pay Codes task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Run pre-flight check
if ! preflight_check; then
    echo "FATAL: Pre-flight check failed. Cannot start task."
    exit 1
fi

# Ensure cleanly starting state by deleting any existing pay codes with these names
echo "Cleaning up any pre-existing pay codes for this task..."
docker exec timetrex-postgres psql -U timetrex -d timetrex -c "DELETE FROM pay_code WHERE name IN ('Hazmat Bonus', 'Trainer Premium', 'Lost Equipment Fee');" 2>/dev/null || true

# Record task start time (epoch seconds) for anti-gaming verification
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/task_start_timestamp
echo "Task start timestamp: $TASK_START"

# Take initial screenshot
take_screenshot /tmp/task_initial_screenshot.png

# Final verification - ensure we can see the login page
if ! verify_timetrex_accessible; then
    echo "FATAL: TimeTrex login page not accessible at task start!"
    exit 1
fi

echo ""
echo "=== Task Setup Complete ==="
echo "Task: Create 3 custom Payroll Pay Codes"
echo "  1. Hazmat Bonus (Earning)"
echo "  2. Trainer Premium (Earning)"
echo "  3. Lost Equipment Fee (Deduction)"
echo "Login credentials: demoadmin1 / demo"
echo ""