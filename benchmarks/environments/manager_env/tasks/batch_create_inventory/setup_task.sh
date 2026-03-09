#!/bin/bash
# Setup script for batch_create_inventory task
# Prepares Manager.io and records the initial inventory count.

echo "=== Setting up batch_create_inventory task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure Manager.io is running and accessible
wait_for_manager 60

# 2. Record Task Start Time
date +%s > /tmp/task_start_time.txt

# 3. Get Business Key (needed for API queries)
# We scrape it from the main page redirection
COOKIE_FILE="/tmp/mgr_cookies.txt"
BIZ_KEY=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "http://localhost:8080/businesses" -L | \
    python3 -c "import sys, re; m = re.search(r'start\?([^\"&\s]+)[^<]{0,300}Northwind Traders', sys.stdin.read()); print(m.group(1) if m else '')")

if [ -z "$BIZ_KEY" ]; then
    # Fallback search if not found specifically near Northwind
    BIZ_KEY=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "http://localhost:8080/businesses" -L | \
        python3 -c "import sys, re; m = re.search(r'start\?([^\"&\s]+)', sys.stdin.read()); print(m.group(1) if m else '')")
fi
echo "$BIZ_KEY" > /tmp/biz_key.txt
echo "Business Key: $BIZ_KEY"

# 4. Record Initial Inventory Count
# We fetch the inventory items page and count the rows or use a python script to parse
echo "Recording initial inventory count..."
curl -s -b "$COOKIE_FILE" "http://localhost:8080/inventory-items?$BIZ_KEY" > /tmp/initial_inventory.html

# Simple line count of table rows as a proxy, or use python for accuracy
INITIAL_COUNT=$(python3 -c "import sys; print(sys.stdin.read().count('<tr>') - 1)" < /tmp/initial_inventory.html)
# Adjust if count is negative (empty table might still have headers)
if [ "$INITIAL_COUNT" -lt 0 ]; then INITIAL_COUNT=0; fi

echo "$INITIAL_COUNT" > /tmp/initial_inventory_count.txt
echo "Initial Inventory Count: $INITIAL_COUNT"

# 5. Open Firefox at Inventory Items page
# This puts the agent in the right place to start
echo "Opening Manager.io at Inventory Items..."
open_manager_at "inventory"

# 6. Initial Screenshot
sleep 5
echo "Capturing initial state..."
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="