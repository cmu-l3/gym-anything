#!/bin/bash
set -e
echo "=== Setting up create_delivery_note task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure Manager.io is running
ensure_manager_running

# -----------------------------------------------------------------------
# Setup Manager.io State: Disable Delivery Notes & Ensure Clean Slate
# -----------------------------------------------------------------------
COOKIE_FILE="/tmp/mgr_setup_cookies.txt"
MANAGER_URL="http://localhost:8080"

# 1. Login
curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
    -X POST "$MANAGER_URL/login" \
    -d "Username=administrator" \
    -L -o /dev/null 2>/dev/null

# 2. Get Business Key for Northwind Traders
BIZ_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/businesses" -L 2>/dev/null)
BIZ_KEY=$(python3 -c "
import re, sys
html = sys.stdin.read()
m = re.search(r'start\?([^\"&\s]+)[^<]{0,300}Northwind Traders', html)
if not m:
    m = re.search(r'start\?([^\"&\s]+)', html)
print(m.group(1) if m else '', end='')
" <<< "$BIZ_PAGE")

if [ -z "$BIZ_KEY" ]; then
    echo "ERROR: Northwind Traders business not found."
    exit 1
fi
echo "$BIZ_KEY" > /tmp/manager_biz_key.txt

# 3. Enter Business
curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/start?$BIZ_KEY" -L -o /dev/null 2>/dev/null

# 4. Disable 'DeliveryNotes' tab explicitly to force agent to enable it
# We need to post the configuration to /tabs-form
TABS_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/start?$BIZ_KEY" -L 2>/dev/null)
TABS_URL=$(echo "$TABS_PAGE" | grep -o '/tabs-form?[^"]*' | head -1)

if [ -n "$TABS_URL" ]; then
    # Extract the hidden field name (FileID/Key)
    FORM_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL$TABS_URL" -L 2>/dev/null)
    FIELD_NAME=$(echo "$FORM_PAGE" | grep -o 'name="[^"]*" value="{' | head -1 | grep -o '"[^"]*"' | head -1 | tr -d '"')
    
    if [ -n "$FIELD_NAME" ]; then
        # JSON config WITHOUT DeliveryNotes
        # Standard set: BankAndCash, Receipts, Payments, Customers, SalesInvoices, Suppliers, Inventory
        TABS_JSON='{"BankAndCashAccounts":true,"Receipts":true,"Payments":true,"Customers":true,"SalesInvoices":true,"CreditNotes":true,"Suppliers":true,"PurchaseInvoices":true,"InventoryItems":true,"Reports":true,"Settings":true}'
        
        curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
            -X POST "$MANAGER_URL$TABS_URL" \
            -F "$FIELD_NAME=$TABS_JSON" \
            -L -o /dev/null 2>/dev/null
        echo "Configuration updated: Delivery Notes module DISABLED."
    fi
fi

# 5. Record initial count of delivery notes (should be 0 or inaccessible)
# If disabled, this might return 404 or redirect, which we treat as 0
DN_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/delivery-notes?$BIZ_KEY" -L 2>/dev/null)
INITIAL_COUNT=$(echo "$DN_PAGE" | grep -c "delivery-note-view" || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_dn_count.txt

# -----------------------------------------------------------------------
# UI Setup
# -----------------------------------------------------------------------

# Open Firefox at the Summary page
open_manager_at "summary"

# Capture initial state
sleep 5
echo "Capturing initial screenshot..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="