#!/bin/bash
set -e
echo "=== Setting up Write Off Bad Debt Task ==="

source /workspace/scripts/task_utils.sh

# Ensure Manager is ready
wait_for_manager 60

MANAGER_URL="http://localhost:8080"
COOKIE_FILE="/tmp/mgr_cookies.txt"

# 1. Login to get cookies
curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" -X POST "$MANAGER_URL/login" -d "Username=administrator" -L -o /dev/null

# 2. Get Business Key for "Northwind Traders"
BIZ_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/businesses" -L)
# Extract key from link like /start?key
BIZ_KEY=$(echo "$BIZ_PAGE" | grep -oP 'start\?\K[^"]+(?="[^>]*>Northwind Traders)' | head -1)

if [ -z "$BIZ_KEY" ]; then
    echo "ERROR: Could not find Northwind Traders business key. Re-running setup..."
    bash /workspace/scripts/setup_data.sh
    # Retry
    BIZ_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/businesses" -L)
    BIZ_KEY=$(echo "$BIZ_PAGE" | grep -oP 'start\?\K[^"]+(?="[^>]*>Northwind Traders)' | head -1)
fi

echo "Business Key: $BIZ_KEY"
echo "$BIZ_KEY" > /tmp/biz_key.txt

# 3. Get form token (UUID used for form submissions) - grab from any form
FORM_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/customer-form?$BIZ_KEY")
FORM_TOKEN=$(echo "$FORM_PAGE" | grep -oP 'name="\K[a-f0-9-]{36}(?=" value="{}")' | head -1)

if [ -z "$FORM_TOKEN" ]; then
    # Fallback/Guess if scraping fails (common UUID in this version)
    FORM_TOKEN="febb4049-dcdb-4c7a-a395-4b71da72a85b"
fi
echo "Form Token: $FORM_TOKEN"

# 4. Find Customer UUID for 'Alfreds Futterkiste'
CUST_JSON=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/api/$BIZ_KEY/customers.json")
CUST_KEY=$(echo "$CUST_JSON" | python3 -c "import sys, json; print(next((c['Key'] for c in json.load(sys.stdin) if 'Alfreds' in c['Name']), ''))")

if [ -z "$CUST_KEY" ]; then
    echo "Creating Alfreds Futterkiste..."
    # Create if missing
    curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" -X POST "$MANAGER_URL/customer-form?$BIZ_KEY" \
        -F "$FORM_TOKEN={\"Name\":\"Alfreds Futterkiste\"}" -L -o /dev/null
    # Fetch key again
    CUST_JSON=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/api/$BIZ_KEY/customers.json")
    CUST_KEY=$(echo "$CUST_JSON" | python3 -c "import sys, json; print(next((c['Key'] for c in json.load(sys.stdin) if 'Alfreds' in c['Name']), ''))")
fi
echo "Customer Key: $CUST_KEY"

# 5. Create the "Bad" Invoice (INV-BAD-001) for 500.00
# We use the API endpoint or form submission simulation
echo "Creating Invoice INV-BAD-001..."
INVOICE_DATA='{"Reference":"INV-BAD-001","IssueDate":"'$(date +%Y-%m-%d)'","Customer":"'$CUST_KEY'","BillingAddress":"Obere Str. 57\nBerlin","Lines":[{"Description":"Services Rendered","Amount":500}]}'

curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" -X POST "$MANAGER_URL/sales-invoice-form?$BIZ_KEY" \
    -F "$FORM_TOKEN=$INVOICE_DATA" -L -o /dev/null

# 6. Ensure Credit Notes module is active
# (Handled generically in setup_data.sh, but good to double check)

# 7. Start Firefox
echo "Starting Firefox..."
open_manager_at "summary"

# Record start time
date +%s > /tmp/task_start_time.txt

# Take initial screenshot
sleep 5
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="