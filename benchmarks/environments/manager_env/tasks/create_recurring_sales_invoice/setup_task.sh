#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up task: create_recurring_sales_invoice ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Manager.io is running
ensure_manager_running

# Setup cookies and URL
COOKIE_FILE="/tmp/mgr_setup_cookies.txt"
MANAGER_URL="http://localhost:8080"

# Login
echo "Logging in..."
curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
    -X POST "$MANAGER_URL/login" \
    -d "Username=administrator" -L -o /dev/null 2>/dev/null

# Get Business Key
echo "Getting business key..."
BIZ_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
    "$MANAGER_URL/businesses" -L 2>/dev/null)
BIZ_KEY=$(python3 -c "
import re, sys
html = sys.stdin.read()
m = re.search(r'start\?([^\"&\s]+)[^<]{0,300}Northwind Traders', html)
if not m: m = re.search(r'start\?([^\"&\s]+)', html)
print(m.group(1) if m else '', end='')
" <<< "$BIZ_PAGE")

if [ -z "$BIZ_KEY" ]; then
    echo "ERROR: Could not find Northwind Traders business."
    exit 1
fi
echo "Business Key: $BIZ_KEY"

# Navigate to business to set session context
curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
    "$MANAGER_URL/start?$BIZ_KEY" -L -o /dev/null 2>/dev/null

# Force Disable "Recurring Sales Invoices" to ensure a clean start state
# We only enable the standard set, explicitly excluding RecurringSalesInvoices
echo "Configuring tabs (disabling Recurring Sales Invoices)..."
TABS_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
    "$MANAGER_URL/start?$BIZ_KEY" -L 2>/dev/null)
TABS_URL=$(echo "$TABS_PAGE" | grep -o '/tabs-form?[^"]*' | head -1)

if [ -n "$TABS_URL" ]; then
    FIELD_NAME=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
        "$MANAGER_URL$TABS_URL" -L 2>/dev/null | \
        grep -o 'name="[a-f0-9-]*" value=' | head -1 | \
        grep -o '"[a-f0-9-]*"' | tr -d '"')
    
    if [ -n "$FIELD_NAME" ]; then
        # JSON without RecurringSalesInvoices
        TABS_JSON='{"BankAndCashAccounts":true,"Receipts":true,"Payments":true,"Customers":true,"SalesInvoices":true,"CreditNotes":true,"Suppliers":true,"PurchaseInvoices":true,"DebitNotes":true,"InventoryItems":true,"JournalEntries":true,"Reports":true}'
        
        curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
            -X POST "$MANAGER_URL$TABS_URL" \
            -F "$FIELD_NAME=$TABS_JSON" \
            -L -o /dev/null 2>/dev/null
        echo "Tabs configured."
    fi
fi

# Verify Customer Exists
echo "Verifying customer 'Alfreds Futterkiste'..."
CUST_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
    "$MANAGER_URL/customers?$BIZ_KEY" -L 2>/dev/null)
if ! echo "$CUST_PAGE" | grep -q "Alfreds Futterkiste"; then
    echo "WARNING: Customer not found. Attempting to create..."
    # Fallback creation logic would go here, but Northwind usually has it.
fi

# Open Manager at Summary page (Dashboard)
# This forces the agent to navigate to Settings themselves
open_manager_at "summary"

# Capture initial screenshot
sleep 5
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="