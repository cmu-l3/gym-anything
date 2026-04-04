#!/bin/bash
set -e
echo "=== Setting up create_employee_payslip task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Manager.io is running
wait_for_manager 60

# ==============================================================================
# Record Initial State (Anti-Gaming)
# ==============================================================================
echo "Recording initial state..."
COOKIE_FILE="/tmp/mgr_setup_cookies.txt"
MANAGER_URL="http://localhost:8080"

# Login to get session
curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
    -X POST "$MANAGER_URL/login" \
    -d "Username=administrator" \
    -L -o /dev/null 2>/dev/null

# Get business key for Northwind Traders
BIZ_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
    "$MANAGER_URL/businesses" -L 2>/dev/null)

BIZ_KEY=$(python3 -c "
import re, sys
html = sys.stdin.read()
# Try to find Northwind specifically
m = re.search(r'start\?([^\"&\s]+)[^<]{0,300}Northwind Traders', html)
# Fallback to any business if Northwind not explicitly found (though it should be)
if not m:
    m = re.search(r'start\?([^\"&\s]+)', html)
print(m.group(1) if m else '', end='')
" <<< "$BIZ_PAGE")

if [ -z "$BIZ_KEY" ]; then
    echo "WARNING: Could not determine business key during setup."
    echo "unknown" > /tmp/initial_biz_key.txt
else
    echo "$BIZ_KEY" > /tmp/initial_biz_key.txt
    
    # Check if modules are already enabled (unlikely in fresh env, but good to know)
    # We check by seeing if the endpoints return 200 OK (enabled) or redirect/error
    
    # Check Employees
    HTTP_CODE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
        "$MANAGER_URL/employees?$BIZ_KEY" -L -w "%{http_code}" -o /dev/null 2>/dev/null)
    echo "Initial Employees HTTP: $HTTP_CODE" > /tmp/initial_employees_status.txt
    
    # Check Payslips
    HTTP_CODE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
        "$MANAGER_URL/payslips?$BIZ_KEY" -L -w "%{http_code}" -o /dev/null 2>/dev/null)
    echo "Initial Payslips HTTP: $HTTP_CODE" > /tmp/initial_payslips_status.txt
fi

# ==============================================================================
# Prepare Environment
# ==============================================================================

# Start Firefox at the Settings page
# We use the open_manager_at helper, but pointing to 'settings'
echo "Opening Manager.io at Settings page..."
open_manager_at "settings"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="