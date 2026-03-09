#!/bin/bash
# Setup script for record_customer_receipt task
# Records initial receipt count and opens Manager.io

set -e

echo "=== Setting up record_customer_receipt task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure Manager.io is running
wait_for_manager 60

# 2. Record Task Start Time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 3. Get Session and Business Key (to record initial state)
COOKIE_FILE="/tmp/mgr_setup_cookies.txt"
MANAGER_URL="http://localhost:8080"

# Login
curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" -X POST "$MANAGER_URL/login" -d "Username=administrator" -L -o /dev/null

# Get Business Key for Northwind Traders
BIZ_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/businesses" -L)
BIZ_KEY=$(python3 -c "import sys, re; m = re.search(r'start\?([^\"&\s]+)[^<]{0,300}Northwind Traders', sys.stdin.read()); print(m.group(1) if m else '')" <<< "$BIZ_PAGE")

if [ -z "$BIZ_KEY" ]; then
    echo "WARNING: Could not find Northwind Traders business key. Verification might be limited."
    echo "0" > /tmp/initial_receipt_count.txt
else
    # Navigate to business to set session context
    curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/start?$BIZ_KEY" -L -o /dev/null
    
    # Get Receipts Page and count existing receipts
    # Note: Manager.io URL for receipts is usually /receipts?FileID=...
    RECEIPTS_HTML=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/receipts?$BIZ_KEY" -L)
    
    # Simple count of table rows or specific markers. 
    # Manager tables usually have a View button or Edit button for each row.
    INITIAL_COUNT=$(echo "$RECEIPTS_HTML" | grep -c "View" || echo "0")
    echo "$INITIAL_COUNT" > /tmp/initial_receipt_count.txt
    echo "Initial receipts count: $INITIAL_COUNT"
fi

# 4. Open Firefox at the Dashboard (Summary)
# We start at the dashboard to force the agent to navigate to Receipts
echo "Opening Manager.io at Summary page..."
open_manager_at "summary"

# 5. Take Initial Screenshot
sleep 5
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="