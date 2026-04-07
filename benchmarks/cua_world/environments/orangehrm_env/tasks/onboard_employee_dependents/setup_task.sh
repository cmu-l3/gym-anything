#!/bin/bash
set -e
echo "=== Setting up Onboard Employee Dependents task ==="

source /workspace/scripts/task_utils.sh

# 1. Wait for OrangeHRM
wait_for_http "$ORANGEHRM_URL" 60

# 2. Clean up previous runs
# Soft-delete any existing "James Holden" to ensure a clean state
echo "Cleaning up previous 'James Holden' records..."
EXISTING_IDS=$(orangehrm_db_query "SELECT emp_number FROM hs_hr_employee WHERE emp_firstname='James' AND emp_lastname='Holden' AND purged_at IS NULL;" 2>/dev/null)

if [ -n "$EXISTING_IDS" ]; then
    # Convert newlines to commas for SQL IN clause if multiple
    IDS_FORMATTED=$(echo "$EXISTING_IDS" | tr '\n' ',' | sed 's/,$//')
    if [ -n "$IDS_FORMATTED" ]; then
        orangehrm_db_query "UPDATE hs_hr_employee SET purged_at=NOW() WHERE emp_number IN ($IDS_FORMATTED);"
        echo "Soft-deleted employee(s) with ID(s): $IDS_FORMATTED"
    fi
fi

# 3. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 4. Start Browser and Login
# We start at the Dashboard to force navigation to PIM
TARGET_URL="${ORANGEHRM_URL}/web/index.php/dashboard/index"
ensure_orangehrm_logged_in "$TARGET_URL"

# 5. Take initial screenshot
sleep 3
take_screenshot /tmp/task_initial.png
echo "Initial screenshot captured."

echo "=== Task setup complete ==="