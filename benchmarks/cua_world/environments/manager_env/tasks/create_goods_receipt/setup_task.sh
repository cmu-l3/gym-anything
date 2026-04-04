#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up Goods Receipt task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Manager.io is running
ensure_manager_running

# Record initial state: Goods Receipts module should NOT be enabled
COOKIE_FILE="/tmp/mgr_setup_cookies.txt"
curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
    -X POST "$MANAGER_URL/login" -d "Username=administrator" -L -o /dev/null

# Get business key
BIZ_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/businesses" -L)
BIZ_KEY=$(echo "$BIZ_PAGE" | python3 -c "
import sys, re
html = sys.stdin.read()
m = re.search(r'start\?([^\"&\s]+)', html)
print(m.group(1) if m else '', end='')
")

if [ -z "$BIZ_KEY" ]; then
    echo "ERROR: Could not find Northwind business key."
    exit 1
fi

echo "Business Key: $BIZ_KEY"

# Check if Goods Receipts module is already enabled
BIZ_START=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/start?$BIZ_KEY" -L)
if echo "$BIZ_START" | grep -qi "goods-receipts"; then
    echo "WARNING: Goods Receipts already enabled. Task starting from non-ideal state."
    echo "enabled" > /tmp/manager_task_gr_module_initial
else
    echo "not_enabled" > /tmp/manager_task_gr_module_initial
fi

# Record initial goods receipt count (should be 0)
# Note: If module is disabled, this URL might redirect, so we handle that gracefully
GR_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/goods-receipts?$BIZ_KEY" -L 2>/dev/null)
GR_COUNT=$(echo "$GR_PAGE" | grep -c 'goods-receipt-view' 2>/dev/null || echo "0")
echo "$GR_COUNT" > /tmp/manager_task_gr_count_initial
echo "Initial goods receipt count: $GR_COUNT"

# Open Firefox at the Summary page (Dashboard)
# We do NOT navigate to goods receipts because the agent must enable it first
open_manager_at "summary"

# Take initial screenshot
sleep 5
take_screenshot /tmp/task_initial.png

echo "=== Goods Receipt task setup complete ==="