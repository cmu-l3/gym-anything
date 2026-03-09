#!/bin/bash
set -e
echo "=== Setting up record_bank_transfer task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Manager.io is running
ensure_manager_running

COOKIE_FILE="/tmp/mgr_setup_cookies.txt"
rm -f "$COOKIE_FILE"

# ---------------------------------------------------------------------------
# Step 1: Login and get Business Key
# ---------------------------------------------------------------------------
echo "Logging into Manager.io..."
curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
    -X POST "$MANAGER_URL/login" \
    -d "Username=administrator" \
    -L -o /dev/null

BIZ_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/businesses" -L)

# Extract Northwind key
BIZ_KEY=$(python3 -c "
import re, sys
html = sys.stdin.read()
m = re.search(r'start\?([^\"&\s]+)[^<]{0,300}Northwind Traders', html)
if not m:
    m = re.search(r'start\?([^\"&\s]+)', html)
print(m.group(1) if m else '', end='')
" <<< "$BIZ_PAGE")

if [ -z "$BIZ_KEY" ]; then
    echo "ERROR: Could not find Northwind Traders business."
    exit 1
fi
echo "Business Key: $BIZ_KEY"
echo "$BIZ_KEY" > /tmp/manager_biz_key.txt

# Navigate to business context
curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/start?$BIZ_KEY" -L -o /dev/null

# ---------------------------------------------------------------------------
# Step 2: Enable InterAccountTransfers Module
# ---------------------------------------------------------------------------
echo "Enabling Inter Account Transfers module..."
# Get tabs form to find the field name
TABS_URL="/tabs-form?$BIZ_KEY"
TABS_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL$TABS_URL" -L)
TABS_FIELD=$(echo "$TABS_PAGE" | grep -o 'name="[a-f0-9-]*"' | head -1 | sed 's/name="//;s/"//')

if [ -n "$TABS_FIELD" ]; then
    # Enable common tabs + InterAccountTransfers
    TABS_JSON='{"BankAndCashAccounts":true,"Receipts":true,"Payments":true,"InterAccountTransfers":true,"Customers":true,"SalesInvoices":true,"CreditNotes":true,"Suppliers":true,"PurchaseInvoices":true,"DebitNotes":true,"InventoryItems":true,"JournalEntries":true,"Reports":true}'
    curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
        -X POST "$MANAGER_URL$TABS_URL" \
        -F "$TABS_FIELD=$TABS_JSON" \
        -L -o /dev/null
fi

# ---------------------------------------------------------------------------
# Step 3: Create "Business Checking Account"
# ---------------------------------------------------------------------------
# Need the generic form field UUID for this business
FORM_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/customer-form?$BIZ_KEY" -L)
FIELD_NAME=$(echo "$FORM_PAGE" | grep -o 'name="[a-f0-9-]*" value="{}"' | head -1 | grep -o '"[a-f0-9-]*"' | head -1 | tr -d '"')

if [ -n "$FIELD_NAME" ]; then
    # Check if exists
    BANK_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/bank-and-cash-accounts?$BIZ_KEY" -L)
    if ! echo "$BANK_PAGE" | grep -q "Business Checking Account"; then
        echo "Creating Business Checking Account..."
        BANK_JSON='{"Name":"Business Checking Account"}'
        curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
            -X POST "$MANAGER_URL/bank-or-cash-account-form?$BIZ_KEY" \
            -F "$FIELD_NAME=$BANK_JSON" \
            -L -o /dev/null
    fi
fi

# ---------------------------------------------------------------------------
# Step 4: Record Initial State
# ---------------------------------------------------------------------------
TRANSFERS_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/inter-account-transfers?$BIZ_KEY" -L)
INITIAL_COUNT=$(echo "$TRANSFERS_PAGE" | grep -c 'inter-account-transfer?' || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_transfer_count.txt
echo "Initial transfer count: $INITIAL_COUNT"

# ---------------------------------------------------------------------------
# Step 5: Launch Firefox
# ---------------------------------------------------------------------------
echo "Opening Firefox at Summary page..."
open_manager_at "summary"

# Wait for load and take screenshot
sleep 8
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="