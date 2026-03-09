#!/bin/bash
echo "=== Setting up record_net_deposit_receipt task ==="

source /workspace/scripts/task_utils.sh

# Ensure Manager is running
wait_for_manager 60

# Record start time
date +%s > /tmp/task_start_time.txt
echo "Task start: $(cat /tmp/task_start_time.txt)"

# ---------------------------------------------------------------------------
# Setup Data: Create specific Invoice and Expense Account via API
# ---------------------------------------------------------------------------
MANAGER_URL="http://localhost:8080"
COOKIE_FILE="/tmp/mgr_setup_cookies.txt"

# Login
curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" -X POST "$MANAGER_URL/login" -d "Username=administrator" -L -o /dev/null

# Get Business Key (Northwind Traders)
BIZ_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/businesses" -L)
BIZ_KEY=$(echo "$BIZ_PAGE" | grep -o 'start?[^"]*' | head -1 | cut -d? -f2)

if [ -z "$BIZ_KEY" ]; then
    echo "ERROR: Could not find Northwind Traders business key."
    # Fallback to coordinate navigation if API fails, but usually setup_manager.sh ensures it exists
    exit 1
fi
echo "Business Key: $BIZ_KEY"

# Navigate to business to set session context
curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/start?$BIZ_KEY" -L -o /dev/null

# Helper to find UUID by name
get_uuid_by_name() {
    local endpoint=$1
    local name=$2
    curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/$endpoint?$BIZ_KEY" -L | \
    grep -B 5 ">$name<" | grep -o 'key=[^"]*' | head -1 | cut -d= -f2
}

# 1. Get Customer UUID (Alfreds Futterkiste)
CUST_UUID=$(get_uuid_by_name "customers" "Alfreds Futterkiste")
echo "Customer UUID: $CUST_UUID"

# 2. Ensure 'Bank Service Charges' expense account exists
EXP_UUID=$(get_uuid_by_name "expense-accounts" "Bank Service Charges")
if [ -z "$EXP_UUID" ]; then
    echo "Creating 'Bank Service Charges' account..."
    # Get form token
    FORM_HTML=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/expense-account-form?$BIZ_KEY" -L)
    TOKEN_NAME=$(echo "$FORM_HTML" | grep -o 'name="[a-f0-9-]*" value="{}"' | head -1 | grep -o '"[a-f0-9-]*"' | head -1 | tr -d '"')
    
    # Create account
    JSON='{"Name":"Bank Service Charges","Code":"6050"}'
    curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" -X POST "$MANAGER_URL/expense-account-form?$BIZ_KEY" \
        -F "$TOKEN_NAME=$JSON" -L -o /dev/null
    
    EXP_UUID=$(get_uuid_by_name "expense-accounts" "Bank Service Charges")
fi
echo "Expense Account UUID: $EXP_UUID"

# 3. Create Sales Invoice #INV-STRIPE-001
# Check if exists first
EXISTING_INV=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/sales-invoices?$BIZ_KEY" -L | grep "INV-STRIPE-001")

if [ -z "$EXISTING_INV" ]; then
    echo "Creating Invoice #INV-STRIPE-001..."
    # Get form token
    FORM_HTML=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/sales-invoice-form?$BIZ_KEY" -L)
    TOKEN_NAME=$(echo "$FORM_HTML" | grep -o 'name="[a-f0-9-]*" value="{}"' | head -1 | grep -o '"[a-f0-9-]*"' | head -1 | tr -d '"')
    
    # Create Invoice JSON
    # Lines structure: Item (Description), Qty, UnitPrice, Account (usually default sales)
    INV_JSON='{"IssueDate":"'$(date +%Y-%m-%d)'","Reference":"INV-STRIPE-001","Customer":"'$CUST_UUID'","BillingAddress":"Obere Str. 57\nBerlin 12209\nGermany","Lines":[{"Description":"Consulting Services","Qty":1,"UnitPrice":500}]}'
    
    curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" -X POST "$MANAGER_URL/sales-invoice-form?$BIZ_KEY" \
        -F "$TOKEN_NAME=$INV_JSON" -L -o /dev/null
else
    echo "Invoice #INV-STRIPE-001 already exists."
fi

# ---------------------------------------------------------------------------
# Initial State Recording
# ---------------------------------------------------------------------------
# Record initial bank balance for "Cash on Hand"
# We'll scrape the Summary page or Bank Accounts page
BANK_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/bank-and-cash-accounts?$BIZ_KEY" -L)
# Simple grep for the balance next to Cash on Hand is tricky, relying on verification of the *transaction* is better.
# But let's try to get a rough count of receipts.
RECEIPTS_COUNT=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/receipts?$BIZ_KEY" -L | grep -c "View")
echo "$RECEIPTS_COUNT" > /tmp/initial_receipt_count.txt

# ---------------------------------------------------------------------------
# UI Setup
# ---------------------------------------------------------------------------
# Open Manager at Receipts module to save agent time
open_manager_at "receipts"

# Maximize window
sleep 5
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="