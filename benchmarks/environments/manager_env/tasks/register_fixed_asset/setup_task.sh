#!/bin/bash
echo "=== Setting up register_fixed_asset task ==="

source /workspace/scripts/task_utils.sh

# Ensure Manager.io is running and accessible
wait_for_manager 60

# Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# ---------------------------------------------------------------------------
# Ensure "Fixed Assets" module is DISABLED initially
# ---------------------------------------------------------------------------
echo "Configuring initial state (Fixed Assets disabled)..."

# Login and get cookie
COOKIE_FILE="/tmp/mgr_cookies.txt"
curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" -X POST "$MANAGER_URL/login" -d "Username=administrator" -L -o /dev/null

# Get Business Key for Northwind
BIZ_PAGE=$(curl -s -b "$COOKIE_FILE" "$MANAGER_URL/businesses" -L)
BIZ_KEY=$(echo "$BIZ_PAGE" | grep -o 'start?[^"]*' | grep -v "create-new-business" | head -1 | cut -d'?' -f2)

if [ -z "$BIZ_KEY" ]; then
    echo "ERROR: Could not find Northwind Traders business key"
    # Fallback to coordinate navigation if API fails, but usually setup_data.sh handles this
else
    echo "Business Key: $BIZ_KEY"
    
    # Check if Fixed Assets is already enabled
    SUMMARY_PAGE=$(curl -s -b "$COOKIE_FILE" "$MANAGER_URL/summary?$BIZ_KEY" -L)
    if echo "$SUMMARY_PAGE" | grep -q "Fixed Assets"; then
        echo "Fixed Assets enabled - disabling it for task start..."
        
        # Get the Customize/Tabs form URL
        # Note: The URL is usually /tabs-form?Key=...
        TABS_FORM_URL="$MANAGER_URL/tabs-form?$BIZ_KEY"
        
        # We need the FileID/Key specific to the form submission if hidden fields exist
        # But Manager often accepts just the JSON blob for tabs
        
        # Define tabs WITHOUT FixedAssets (Standard Northwind set)
        TABS_JSON='{"BankAndCashAccounts":true,"Receipts":true,"Payments":true,"Customers":true,"SalesInvoices":true,"CreditNotes":true,"Suppliers":true,"PurchaseInvoices":true,"DebitNotes":true,"InventoryItems":true,"JournalEntries":true,"Reports":true}'
        
        # Find the form field name for the JSON object
        FORM_HTML=$(curl -s -b "$COOKIE_FILE" "$TABS_FORM_URL" -L)
        FIELD_NAME=$(echo "$FORM_HTML" | grep -o 'name="[^"]*" value="{}"' | head -1 | grep -o 'name="[^"]*"' | sed 's/name="//;s/"//')
        
        if [ -n "$FIELD_NAME" ]; then
            curl -s -b "$COOKIE_FILE" -X POST "$TABS_FORM_URL" -F "$FIELD_NAME=$TABS_JSON" -L -o /dev/null
            echo "Fixed Assets module disabled."
        else
            echo "WARNING: Could not disable Fixed Assets (form field not found)"
        fi
    else
        echo "Fixed Assets is already disabled (Good)."
    fi
fi

# ---------------------------------------------------------------------------
# Start Firefox at Summary
# ---------------------------------------------------------------------------
echo "Opening Manager.io at Summary..."
open_manager_at "summary"

# Take initial screenshot
sleep 5
echo "Capturing initial state..."
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="