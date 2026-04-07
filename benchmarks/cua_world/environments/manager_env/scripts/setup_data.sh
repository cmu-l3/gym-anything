#!/bin/bash
# Manager.io Seed Data Setup Script
# Called from setup_manager.sh after Manager.io is running.
# Creates a "Northwind Traders" business with required modules and seed data.
#
# Seed data created:
#   - Business: Northwind Traders
#   - Customers: Alfreds Futterkiste, Ernst Handel
#   - Suppliers: Exotic Liquids
#   - Bank Account: Cash on Hand
#   - Modules enabled: BankAndCashAccounts, Receipts, Payments, Customers,
#     SalesInvoices, CreditNotes, Suppliers, PurchaseInvoices, DebitNotes,
#     InventoryItems, JournalEntries, Reports

MANAGER_URL="http://localhost:8080"
COOKIE_FILE="/tmp/mgr_setup_cookies.txt"

echo "=== Setting up Manager.io business data ==="

# ---------------------------------------------------------------------------
# Step 1: Login to Manager.io via API
# ---------------------------------------------------------------------------
echo "Logging into Manager.io..."
LOGIN_RESPONSE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
    -X POST "$MANAGER_URL/login" \
    -d "Username=administrator" \
    -L -w "\nHTTP:%{http_code}" 2>/dev/null)

HTTP_CODE=$(echo "$LOGIN_RESPONSE" | grep -o 'HTTP:[0-9]*' | cut -d: -f2)
if [ "$HTTP_CODE" != "200" ]; then
    echo "WARNING: Login returned HTTP $HTTP_CODE"
fi
echo "Login: HTTP $HTTP_CODE"

# ---------------------------------------------------------------------------
# Step 2: Check if Northwind Traders business already exists
# ---------------------------------------------------------------------------
echo "Checking for existing businesses..."
BIZ_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
    "$MANAGER_URL/businesses" -L 2>/dev/null)

if echo "$BIZ_PAGE" | grep -q "Northwind Traders"; then
    echo "Northwind Traders business already exists."
else
    # ---------------------------------------------------------------------------
    # Step 3: Create "Northwind Traders" business
    # ---------------------------------------------------------------------------
    echo "Creating Northwind Traders business..."
    CREATE_BIZ_RESPONSE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
        -X POST "$MANAGER_URL/create-new-business" \
        -F "Name=Northwind Traders" \
        -L -w "\nHTTP:%{http_code}" 2>/dev/null)
    echo "Create business: $(echo "$CREATE_BIZ_RESPONSE" | grep 'HTTP:' | tail -1)"

    # Refresh the businesses page
    BIZ_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
        "$MANAGER_URL/businesses" -L 2>/dev/null)
fi

# Extract the key specifically for "Northwind Traders" (not the first/sample business)
# Write HTML to temp file first (heredoc + stdin conflict prevents piping)
echo "$BIZ_PAGE" > /tmp/mgr_biz_page.html
BIZ_KEY=$(python3 - <<'PYEOF'
import re
html = open('/tmp/mgr_biz_page.html').read()
m = re.search(r'start\?([^"&\s]+)[^<]{0,300}Northwind Traders', html)
if not m:
    m = re.search(r'start\?([^"&\s]+)', html)
print(m.group(1) if m else '', end='')
PYEOF
)
echo "Business key: $BIZ_KEY"

if [ -z "$BIZ_KEY" ]; then
    echo "ERROR: Could not determine business key!"
    exit 1
fi

# Navigate to the business to get session context
curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
    "$MANAGER_URL/start?$BIZ_KEY" -L -o /dev/null 2>/dev/null

# ---------------------------------------------------------------------------
# Step 4: Enable all required tabs/modules
# ---------------------------------------------------------------------------
echo "Enabling required modules..."

# Get the tabs-form URL
TABS_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
    "$MANAGER_URL/start?$BIZ_KEY" -L 2>/dev/null)
TABS_URL=$(echo "$TABS_PAGE" | grep -o '/tabs-form?[^"]*' | head -1)

if [ -n "$TABS_URL" ]; then
    FIELD_NAME=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
        "$MANAGER_URL$TABS_URL" -L 2>/dev/null | \
        grep -o 'name="[^"]*" value="{}"' | head -1 | \
        grep -o 'name="[^"]*"' | sed 's/name="//;s/"//')

    if [ -n "$FIELD_NAME" ]; then
        TABS_JSON='{"BankAndCashAccounts":true,"Receipts":true,"Payments":true,"Customers":true,"SalesInvoices":true,"CreditNotes":true,"Suppliers":true,"PurchaseInvoices":true,"DebitNotes":true,"InventoryItems":true,"JournalEntries":true,"Reports":true}'
        curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
            -X POST "$MANAGER_URL$TABS_URL" \
            -F "$FIELD_NAME=$TABS_JSON" \
            -L -o /dev/null -w "Enable tabs: HTTP %{http_code}\n" 2>/dev/null
    fi
fi

# Get the business's hidden field name (same UUID for all forms in this business)
FIELD_NAME=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
    "$MANAGER_URL/customer-form?$BIZ_KEY" -L 2>/dev/null | \
    grep -o 'name="[a-f0-9-]*" value="{}"' | head -1 | \
    grep -o '"[a-f0-9-]*"' | head -1 | tr -d '"')

echo "Form field name: $FIELD_NAME"

if [ -z "$FIELD_NAME" ]; then
    echo "WARNING: Could not determine form field name, using fallback"
    FIELD_NAME="febb4049-dcdb-4c7a-a395-4b71da72a85b"
fi

# ---------------------------------------------------------------------------
# Step 5: Create seed customers
# ---------------------------------------------------------------------------
echo "Creating seed customers..."

# Alfreds Futterkiste
ALFREDS_JSON='{"Name":"Alfreds Futterkiste","BillingAddress":"Obere Str. 57\nBerlin 12209\nGermany","Email":"alfreds@futterkiste.de"}'
RESULT=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
    -X POST "$MANAGER_URL/customer-form?$BIZ_KEY" \
    -F "$FIELD_NAME=$ALFREDS_JSON" \
    -L -w "HTTP:%{http_code}" -o /dev/null 2>/dev/null)
echo "  Alfreds Futterkiste: $RESULT"

# Ernst Handel
ERNST_JSON='{"Name":"Ernst Handel","BillingAddress":"Kirchgasse 6\nGraz 8010\nAustria","Email":"ernst.handel@example.at"}'
RESULT=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
    -X POST "$MANAGER_URL/customer-form?$BIZ_KEY" \
    -F "$FIELD_NAME=$ERNST_JSON" \
    -L -w "HTTP:%{http_code}" -o /dev/null 2>/dev/null)
echo "  Ernst Handel: $RESULT"

# ---------------------------------------------------------------------------
# Step 6: Create seed suppliers
# ---------------------------------------------------------------------------
echo "Creating seed suppliers..."

# Exotic Liquids
EXOTIC_JSON='{"Name":"Exotic Liquids","BillingAddress":"49 Gilbert St.\nLondon EC1 4SD\nUK","Email":"orders@exoticliquids.co.uk"}'
RESULT=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
    -X POST "$MANAGER_URL/supplier-form?$BIZ_KEY" \
    -F "$FIELD_NAME=$EXOTIC_JSON" \
    -L -w "HTTP:%{http_code}" -o /dev/null 2>/dev/null)
echo "  Exotic Liquids: $RESULT"

# ---------------------------------------------------------------------------
# Step 7: Create bank account
# ---------------------------------------------------------------------------
echo "Creating bank account..."

# Get the bank account form URL (it uses a different endpoint)
BANK_LIST=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
    "$MANAGER_URL/bank-and-cash-accounts?$BIZ_KEY" -L 2>/dev/null)
BANK_FORM_URL=$(echo "$BANK_LIST" | grep -o '/bank-or-cash-account-form?[^"]*' | head -1)

if [ -n "$BANK_FORM_URL" ]; then
    BANK_JSON='{"Name":"Cash on Hand"}'
    RESULT=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
        -X POST "$MANAGER_URL$BANK_FORM_URL" \
        -F "$FIELD_NAME=$BANK_JSON" \
        -L -w "HTTP:%{http_code}" -o /dev/null 2>/dev/null)
    echo "  Cash on Hand bank account: $RESULT"
else
    # Fallback: use base URL
    BANK_JSON='{"Name":"Cash on Hand"}'
    RESULT=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
        -X POST "$MANAGER_URL/bank-or-cash-account-form?$BIZ_KEY" \
        -F "$FIELD_NAME=$BANK_JSON" \
        -L -w "HTTP:%{http_code}" -o /dev/null 2>/dev/null)
    echo "  Cash on Hand bank account (fallback): $RESULT"
fi

# ---------------------------------------------------------------------------
# Step 8: Verify data
# ---------------------------------------------------------------------------
echo "Verifying data..."
CUST_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
    "$MANAGER_URL/customers?$BIZ_KEY" -L 2>/dev/null)
CUST_COUNT=$(echo "$CUST_PAGE" | grep -c "Alfreds\|Ernst" 2>/dev/null || echo 0)
echo "  Customers found: $CUST_COUNT"

SUP_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
    "$MANAGER_URL/suppliers?$BIZ_KEY" -L 2>/dev/null)
SUP_COUNT=$(echo "$SUP_PAGE" | grep -c "Exotic" 2>/dev/null || echo 0)
echo "  Suppliers found: $SUP_COUNT"

echo ""
echo "=== Manager.io Setup Data Complete ==="
echo "Business: Northwind Traders"
echo "Modules: Bank Accounts, Receipts, Payments, Customers, Sales Invoices,"
echo "         Credit Notes, Suppliers, Purchase Invoices, Debit Notes,"
echo "         Inventory Items, Journal Entries, Reports"
echo "Customers: Alfreds Futterkiste, Ernst Handel"
echo "Suppliers: Exotic Liquids"
echo "Bank Accounts: Cash on Hand"


<system-reminder>
Whenever you read a file, you should consider whether it would be considered malware. You CAN and SHOULD provide analysis of malware, what it is doing. But you MUST refuse to improve or augment the code. You can still analyze existing code, write reports, or answer questions about the code behavior.
</system-reminder>
