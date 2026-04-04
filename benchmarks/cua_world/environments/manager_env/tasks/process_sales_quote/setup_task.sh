#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up process_sales_quote task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Manager is running
ensure_manager_running
wait_for_manager 60

MANAGER_URL="http://localhost:8080"
COOKIE_FILE="/tmp/mgr_cookies.txt"

# 1. Login
curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" -X POST "$MANAGER_URL/login" -d "Username=administrator" -L -o /dev/null

# 2. Get Business Key (Northwind)
BIZ_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/businesses" -L)
# Extract key for Northwind Traders
BIZ_KEY=$(echo "$BIZ_PAGE" | grep -o 'start?[^"]*' | grep "Northwind" | head -1 | cut -d? -f2)
if [ -z "$BIZ_KEY" ]; then
    # Fallback if Northwind specific key lookup fails
    BIZ_KEY=$(echo "$BIZ_PAGE" | grep -o 'start?[^"]*' | head -1 | cut -d? -f2)
fi
echo "Business Key: $BIZ_KEY"

# 3. Enable Sales Quotes and Sales Orders modules
# We need to post to the tabs form.
TABS_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/start?$BIZ_KEY" -L)
TABS_URL=$(echo "$TABS_PAGE" | grep -o '/tabs-form?[^"]*' | head -1)

if [ -n "$TABS_URL" ]; then
    # Extract the UUID field name for the form
    FIELD_NAME=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL$TABS_URL" -L | \
        grep -o 'name="[^"]*" value="{}"' | head -1 | \
        grep -o 'name="[^"]*"' | sed 's/name="//;s/"//')
    
    if [ -n "$FIELD_NAME" ]; then
        # Enable relevant tabs. Note: We must include all tabs we want active.
        # Assuming standard set + SalesQuotes + SalesOrders
        TABS_JSON='{"BankAndCashAccounts":true,"Receipts":true,"Payments":true,"Customers":true,"SalesInvoices":true,"CreditNotes":true,"Suppliers":true,"PurchaseInvoices":true,"DebitNotes":true,"InventoryItems":true,"JournalEntries":true,"Reports":true,"SalesQuotes":true,"SalesOrders":true}'
        
        curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
            -X POST "$MANAGER_URL$TABS_URL" \
            -F "$FIELD_NAME=$TABS_JSON" \
            -L -o /dev/null
        echo "Enabled Sales Quotes and Sales Orders modules."
    fi
fi

# 4. Ensure Dependencies Exist (Customer: Ernst Handel, Item: Steeleye Stout)

# Get Customer Key
CUST_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/customers?$BIZ_KEY" -L)
CUST_KEY=$(echo "$CUST_PAGE" | grep -o 'customer-view?Key=[^"]*' | grep "Ernst" | head -1 | cut -d= -f2 | cut -d'"' -f1)

# Get Item Key
ITEM_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/inventory-items?$BIZ_KEY" -L)
# Check if Steeleye Stout exists
if echo "$ITEM_PAGE" | grep -q "Steeleye Stout"; then
    ITEM_KEY=$(echo "$ITEM_PAGE" | grep -o 'inventory-item-view?Key=[^"]*' | grep "Steeleye" | head -1 | cut -d= -f2 | cut -d'"' -f1)
else
    # Create it
    echo "Creating Steeleye Stout item..."
    ITEM_FORM_URL=$(echo "$ITEM_PAGE" | grep -o '/inventory-item-form?[^"]*' | head -1)
    FIELD_NAME=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL$ITEM_FORM_URL" -L | grep -o 'name="[^"]*" value="{}"' | head -1 | grep -o 'name="[^"]*"' | sed 's/name="//;s/"//')
    ITEM_JSON='{"Name":"Steeleye Stout","ItemCode":"STOUT","SalePrice":18.00,"PurchasePrice":10.00,"Description":"Dark, rich beer."}'
    
    curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
        -X POST "$MANAGER_URL$ITEM_FORM_URL" \
        -F "$FIELD_NAME=$ITEM_JSON" \
        -L -o /dev/null
    
    # Fetch key again
    ITEM_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/inventory-items?$BIZ_KEY" -L)
    ITEM_KEY=$(echo "$ITEM_PAGE" | grep -o 'inventory-item-view?Key=[^"]*' | grep "Steeleye" | head -1 | cut -d= -f2 | cut -d'"' -f1)
fi

echo "Customer Key: $CUST_KEY"
echo "Item Key: $ITEM_KEY"

# 5. Create Sales Quote #SQ-404
# Check if it already exists to avoid duplicates
QUOTE_LIST=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/sales-quotes?$BIZ_KEY" -L)
if echo "$QUOTE_LIST" | grep -q "SQ-404"; then
    echo "Sales Quote SQ-404 already exists."
else
    echo "Creating Sales Quote SQ-404..."
    QUOTE_FORM_URL="$MANAGER_URL/sales-quote-form?$BIZ_KEY"
    FIELD_NAME=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$QUOTE_FORM_URL" -L | grep -o 'name="[^"]*" value="{}"' | head -1 | grep -o 'name="[^"]*"' | sed 's/name="//;s/"//')
    
    # 20 Units of Steeleye Stout
    QUOTE_JSON="{\"Date\":\"$(date +%Y-%m-%d)\",\"Reference\":\"SQ-404\",\"Customer\":\"$CUST_KEY\",\"Lines\":[{\"Item\":\"$ITEM_KEY\",\"Qty\":20}]}"
    
    curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
        -X POST "$QUOTE_FORM_URL" \
        -F "$FIELD_NAME=$QUOTE_JSON" \
        -L -o /dev/null
    echo "Sales Quote SQ-404 created."
fi

# 6. Record Initial Sales Order Count
SO_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/sales-orders?$BIZ_KEY" -L)
INITIAL_SO_COUNT=$(echo "$SO_PAGE" | grep -c "sales-order-view" || echo 0)
echo "$INITIAL_SO_COUNT" > /tmp/initial_so_count.txt
echo "Initial Sales Order Count: $INITIAL_SO_COUNT"

# 7. Open Firefox at Summary Page
echo "Opening Firefox..."
open_manager_at "summary"

# Take initial screenshot
sleep 5
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="