#!/bin/bash
set -e
echo "=== Setting up setup_billable_time task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Manager is running
wait_for_manager 60

# Authenticate to get session cookies and Business Key
COOKIE_FILE="/tmp/mgr_setup_cookies.txt"
curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
    -X POST "$MANAGER_URL/login" \
    -d "Username=administrator" \
    -L -o /dev/null

# Get Business Key for Northwind Traders
BIZ_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/businesses" -L)
BIZ_KEY=$(echo "$BIZ_PAGE" | python3 -c "
import sys, re
html = sys.stdin.read()
# Try specific Northwind link first
m = re.search(r'start\?([^\"&\s]+)[^<]{0,300}Northwind Traders', html)
if not m:
    # Fallback to any start link
    m = re.search(r'start\?([^\"&\s]+)', html)
print(m.group(1) if m else '', end='')
")

if [ -z "$BIZ_KEY" ]; then
    echo "ERROR: Could not find Northwind Traders business key"
    exit 1
fi

echo "Business Key: $BIZ_KEY"
echo "$BIZ_KEY" > /tmp/biz_key.txt

# Record initial billable time entries count (should be 0 or module disabled)
# We check the billable-time page. If module is disabled, it might still be accessible via URL,
# but usually empty.
BILLABLE_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/billable-time?$BIZ_KEY" -L)
INITIAL_COUNT=$(echo "$BILLABLE_PAGE" | grep -c "<tr>" || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_count.txt

# Ensure Firefox is open at the Summary page
open_manager_at "summary"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="