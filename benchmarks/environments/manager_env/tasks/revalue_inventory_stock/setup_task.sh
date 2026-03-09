#!/bin/bash
set -e
echo "=== Setting up revalue_inventory_stock task ==="

source /workspace/scripts/task_utils.sh

# Ensure Manager is running
wait_for_manager 60

# Record start time
date +%s > /tmp/task_start_time.txt

MANAGER_URL="http://localhost:8080"
COOKIE_FILE="/tmp/mgr_cookies.txt"

# 1. Login and get Business Key
echo "Authenticating..."
curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" -X POST "$MANAGER_URL/login" -d "Username=administrator" -L > /dev/null

# Get Northwind Key
BIZ_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/businesses" -L)
BIZ_KEY=$(python3 -c "import sys, re; m = re.search(r'start\?([^\"&\s]+)[^<]{0,300}Northwind Traders', sys.stdin.read()); print(m.group(1) if m else '')" <<< "$BIZ_PAGE")

if [ -z "$BIZ_KEY" ]; then
    echo "ERROR: Northwind Traders business not found."
    exit 1
fi
echo "Business Key: $BIZ_KEY"
echo "$BIZ_KEY" > /tmp/biz_key.txt

# 2. Disable 'Inventory Revaluations' tab if enabled (to force agent to enable it)
echo "Ensuring Inventory Revaluations module is disabled..."
TABS_URL=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/start?$BIZ_KEY" -L | grep -o '/tabs-form?[^"]*' | head -1)

if [ -n "$TABS_URL" ]; then
    # Get form token
    FORM_HTML=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL$TABS_URL" -L)
    FIELD_NAME=$(echo "$FORM_HTML" | grep -o 'name="[a-f0-9-]*" value="{}"' | head -1 | grep -o '"[a-f0-9-]*"' | tr -d '"')
    
    # Construct JSON with InventoryRevaluations: false
    # We preserve other common tabs to keep the business realistic
    TABS_JSON='{"BankAndCashAccounts":true,"Receipts":true,"Payments":true,"Customers":true,"SalesInvoices":true,"Suppliers":true,"InventoryItems":true,"InventoryRevaluations":false}'
    
    if [ -n "$FIELD_NAME" ]; then
        curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
            -X POST "$MANAGER_URL$TABS_URL" \
            -F "$FIELD_NAME=$TABS_JSON" \
            -L -o /dev/null
        echo "Module disabled."
    fi
fi

# 3. Launch Firefox at Dashboard
echo "Launching Firefox..."
open_manager_at "summary"

# Take initial screenshot
sleep 5
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="