#!/bin/bash
set -e
echo "=== Setting up update_customer_billing task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Ensure Manager.io is running
ensure_manager_running

# 3. Setup Cookies and API access
COOKIE_FILE="/tmp/mgr_setup_cookies.txt"
MANAGER_URL="http://localhost:8080"

# Login
curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
    -X POST "$MANAGER_URL/login" \
    -d "Username=administrator" -L -o /dev/null 2>/dev/null

# Get Business Key for Northwind
BIZ_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/businesses" -L 2>/dev/null)
BIZ_KEY=$(python3 -c "
import re, sys
html = sys.stdin.read()
m = re.search(r'start\?([^\"&\s]+)[^<]{0,300}Northwind Traders', html)
if not m: m = re.search(r'start\?([^\"&\s]+)', html)
print(m.group(1) if m else '', end='')
" <<< "$BIZ_PAGE")

if [ -z "$BIZ_KEY" ]; then
    echo "ERROR: Northwind Traders business not found. Running setup_data.sh..."
    /workspace/scripts/setup_data.sh
    # Retry getting key
    BIZ_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/businesses" -L 2>/dev/null)
    BIZ_KEY=$(python3 -c "import re, sys; html=sys.stdin.read(); m=re.search(r'start\?([^\"&\s]+)[^<]{0,300}Northwind Traders', html); print(m.group(1) if m else '', end='')" <<< "$BIZ_PAGE")
fi

# 4. Verify/Reset 'Ernst Handel' to initial state
# This ensures the task is playable even if previous runs modified it
echo "Ensuring Ernst Handel exists with original data..."
# Note: We can't easily 'reset' specific records via this simple API without complex logic,
# but we can verify it exists. If it was modified in a previous run, the environment 
# should ideally be reset, but we'll record the state.

CUST_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/customers?$BIZ_KEY" -L 2>/dev/null)
if ! echo "$CUST_PAGE" | grep -q "Ernst Handel"; then
    echo "WARNING: Ernst Handel not found. Re-running setup_data.sh to restore..."
    /workspace/scripts/setup_data.sh
fi

# 5. Open Firefox directly to Customers module
# This helps the agent start immediately without navigation overhead
echo "Opening Manager.io at Customers module..."
open_manager_at "customers"

# 6. Capture initial state screenshot
sleep 5
echo "Capturing initial screenshot..."
take_screenshot /tmp/task_initial.png

# Record initial file sizes/times for verification logic
echo "Initial setup complete."