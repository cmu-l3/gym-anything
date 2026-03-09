#!/bin/bash
set -e
echo "=== Setting up record_asset_depreciation task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure Manager is running
wait_for_manager 60

# 2. Prepare Data via API
# We need to:
# a) Get the business key
# b) Ensure Fixed Assets module is enabled
# c) Ensure Depreciation Entries module is DISABLED
# d) Ensure "Ford Transit" asset exists

COOKIE_FILE="/tmp/mgr_cookies.txt"
MANAGER_URL="http://localhost:8080"

# Login
curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" -X POST "$MANAGER_URL/login" -d "Username=administrator" -L -o /dev/null

# Get Business Key (Northwind Traders)
BIZ_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/businesses" -L)
BIZ_KEY=$(echo "$BIZ_PAGE" | grep -o 'start?[^"]*' | head -1 | cut -d'?' -f2)

if [ -z "$BIZ_KEY" ]; then
    echo "ERROR: Could not find business key. Is Northwind installed?"
    # Fallback setup if needed, but assuming env is correct
    exit 1
fi
echo "Business Key: $BIZ_KEY"

# Navigate to business to set session
curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/start?$BIZ_KEY" -L -o /dev/null

# Get the UUID for the tabs form
# The form to customize tabs is usually at /tabs-form
TABS_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/tabs-form?$BIZ_KEY" -L)
# Extract the hidden input name for the struct
# It looks like <input type="hidden" name="[UUID]" value="{...}" />
FORM_ID=$(echo "$TABS_PAGE" | grep -o 'name="[^"]*" value="{}"' | head -1 | grep -o 'name="[^"]*"' | cut -d'"' -f2)

# Define Tabs JSON - explicitly EXCLUDING DepreciationEntries but INCLUDING FixedAssets
# We keep common ones: BankAndCashAccounts, Receipts, Payments, Customers, SalesInvoices, Suppliers, PurchaseInvoices, FixedAssets
TABS_JSON='{"BankAndCashAccounts":true,"Receipts":true,"Payments":true,"Customers":true,"SalesInvoices":true,"Suppliers":true,"PurchaseInvoices":true,"FixedAssets":true,"DepreciationEntries":false}'

echo "Configuring modules (Disabling DepreciationEntries)..."
curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
    -X POST "$MANAGER_URL/tabs-form?$BIZ_KEY" \
    -F "$FORM_ID=$TABS_JSON" \
    -L -o /dev/null

# Create "Ford Transit" Fixed Asset
# First, find Fixed Assets form UUID
FA_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/fixed-asset-form?$BIZ_KEY" -L)
FA_FORM_ID=$(echo "$FA_PAGE" | grep -o 'name="[^"]*" value="{}"' | head -1 | grep -o 'name="[^"]*"' | cut -d'"' -f2)

if [ -n "$FA_FORM_ID" ]; then
    echo "Creating Ford Transit asset..."
    # Basic asset JSON
    ASSET_JSON='{"Name":"Ford Transit","DepreciationRate":15}'
    curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
        -X POST "$MANAGER_URL/fixed-asset-form?$BIZ_KEY" \
        -F "$FA_FORM_ID=$ASSET_JSON" \
        -L -o /dev/null
else
    echo "WARNING: Could not find Fixed Asset form ID. Asset might not be created."
fi

# 3. Save initial state timestamp
date +%s > /tmp/task_start_time.txt
echo "0" > /tmp/initial_depreciation_count.txt

# 4. Launch Firefox
# Kill existing to be safe
pkill -f firefox || true
sleep 2

# Start Firefox at Dashboard
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid firefox \
    -profile '/home/ga/.mozilla/firefox/manager.profile' \
    --new-window '$MANAGER_URL/start?$BIZ_KEY' \
    > /tmp/firefox_task.log 2>&1 &"

# Wait for window
wait_for_window "Firefox" 30

# Maximize
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 5. Take Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="