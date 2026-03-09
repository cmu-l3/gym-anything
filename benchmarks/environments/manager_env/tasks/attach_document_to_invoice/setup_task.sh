#!/bin/bash
# Setup script for attach_document_to_invoice task
# 1. Creates a dummy PDF file on the Desktop/Documents
# 2. Creates a specific Sales Invoice (#INV-2024-001) in Manager.io via API
# 3. Opens Firefox at the Sales Invoices list

set -e

echo "=== Setting up attach_document_to_invoice task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure Manager is running
wait_for_manager 60

# 2. Create the dummy PDF file
mkdir -p /home/ga/Documents
cat > /home/ga/Documents/proof_of_delivery.pdf << EOF
%PDF-1.4
%
1 0 obj
<</Type/Catalog/Pages 2 0 R>>
endobj
2 0 obj
<</Type/Pages/Kids[3 0 R]/Count 1>>
endobj
3 0 obj
<</Type/Page/MediaBox[0 0 595 842]>>
endobj
xref
0 4
0000000000 65535 f
0000000010 00000 n
0000000060 00000 n
0000000110 00000 n
trailer
<</Size 4/Root 1 0 R>>
startxref
160
%%EOF
EOF
chown ga:ga /home/ga/Documents/proof_of_delivery.pdf
echo "Created /home/ga/Documents/proof_of_delivery.pdf"

# 3. Create the specific Invoice via API
MANAGER_URL="http://localhost:8080"
COOKIE_FILE="/tmp/mgr_setup_cookies.txt"
INVOICE_REF="INV-2024-001"

echo "Logging in to API..."
curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" -X POST "$MANAGER_URL/login" -d "Username=administrator" -L -o /dev/null

echo "Getting Business Key..."
BIZ_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/businesses" -L)
# Extract Northwind key
BIZ_KEY=$(python3 -c "import sys, re; m = re.search(r'start\?([^\"&\s]+)[^<]{0,300}Northwind Traders', sys.stdin.read()); print(m.group(1) if m else '')" <<< "$BIZ_PAGE")

if [ -z "$BIZ_KEY" ]; then
    echo "ERROR: Northwind Traders business not found."
    exit 1
fi

echo "Business Key: $BIZ_KEY"

# Navigate to business to set session context
curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/start?$BIZ_KEY" -L -o /dev/null

# Get a Customer UUID (Alfreds Futterkiste)
CUST_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/customers?$BIZ_KEY" -L)
CUST_KEY=$(python3 -c "import sys, re; m = re.search(r'customer-view\?([^\"&\s]+)[^<]{0,300}Alfreds', sys.stdin.read()); print(m.group(1) if m else '')" <<< "$CUST_PAGE")

# If Alfreds not found, grab any customer
if [ -z "$CUST_KEY" ]; then
    CUST_KEY=$(python3 -c "import sys, re; m = re.search(r'customer-view\?([^\"&\s]+)', sys.stdin.read()); print(m.group(1) if m else '')" <<< "$CUST_PAGE")
fi

if [ -z "$CUST_KEY" ]; then
    echo "ERROR: No customers found. Cannot create invoice."
    exit 1
fi

echo "Customer Key: $CUST_KEY"

# Get Form Key (Anti-CSRF/State token)
FORM_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/sales-invoice-form?$BIZ_KEY" -L)
FORM_KEY=$(echo "$FORM_PAGE" | grep -o 'name="[a-f0-9-]*" value="{}"' | head -1 | grep -o '"[a-f0-9-]*"' | head -1 | tr -d '"')

if [ -z "$FORM_KEY" ]; then
    # Fallback to known UUID pattern if regex fails
    FORM_KEY="febb4049-dcdb-4c7a-a395-4b71da72a85b" 
    echo "WARNING: Could not scrape form key, using fallback: $FORM_KEY"
fi

# Check if invoice already exists
INVOICES_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/sales-invoices?$BIZ_KEY" -L)
if echo "$INVOICES_PAGE" | grep -q "$INVOICE_REF"; then
    echo "Invoice $INVOICE_REF already exists."
else
    echo "Creating Invoice $INVOICE_REF..."
    # JSON payload for new invoice
    # Note: Manager APIs use a specific structure. Simplest way is to post to the form endpoint.
    INVOICE_JSON="{\"IssueDate\":\"$(date +%Y-%m-%d)\",\"Reference\":\"$INVOICE_REF\",\"Customer\":\"$CUST_KEY\",\"Lines\":[{\"Item\":null,\"Description\":\"Service Fee\",\"Qty\":1,\"UnitPrice\":500}]}"
    
    curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
        -X POST "$MANAGER_URL/sales-invoice-form?$BIZ_KEY" \
        -F "$FORM_KEY=$INVOICE_JSON" \
        -L -o /dev/null
    
    echo "Invoice created."
fi

# 4. Open Manager at Sales Invoices
echo "Opening Firefox at Sales Invoices..."
open_manager_at "sales_invoices"

# Record Task Start Time
date +%s > /tmp/task_start_time.txt
# Record initial attachment count (0)
echo "0" > /tmp/initial_attachment_count.txt

echo "=== Setup Complete ==="