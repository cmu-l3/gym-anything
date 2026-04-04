#!/bin/bash
# Export script for attach_document_to_invoice task
# Verifies if the file is attached to invoice #INV-2024-001

echo "=== Exporting Results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Verify Attachment via API
MANAGER_URL="http://localhost:8080"
COOKIE_FILE="/tmp/mgr_export_cookies.txt"
INVOICE_REF="INV-2024-001"
EXPECTED_FILE="proof_of_delivery.pdf"

echo "Logging in to API..."
curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" -X POST "$MANAGER_URL/login" -d "Username=administrator" -L -o /dev/null

echo "Getting Business Key..."
BIZ_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/businesses" -L)
BIZ_KEY=$(python3 -c "import sys, re; m = re.search(r'start\?([^\"&\s]+)[^<]{0,300}Northwind Traders', sys.stdin.read()); print(m.group(1) if m else '')" <<< "$BIZ_PAGE")

ATTACHMENT_FOUND="false"
ATTACHMENT_NAME=""
INVOICE_FOUND="false"

if [ -n "$BIZ_KEY" ]; then
    # Set context
    curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/start?$BIZ_KEY" -L -o /dev/null

    # Find the Invoice Key
    echo "Searching for invoice $INVOICE_REF..."
    INVOICES_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/sales-invoices?$BIZ_KEY" -L)
    
    # Extract the View UUID for the specific invoice reference
    # HTML link looks like: <a href="/sales-invoice-view?Key=...">INV-2024-001</a>
    INVOICE_KEY=$(echo "$INVOICES_PAGE" | grep -o "sales-invoice-view?[^\"]*" | grep -B 1 "$INVOICE_REF" | head -1 | sed 's/sales-invoice-view?//')
    
    # Fallback regex if grep pipe fails
    if [ -z "$INVOICE_KEY" ]; then
         INVOICE_KEY=$(python3 -c "import sys, re; m = re.search(r'sales-invoice-view\?([^\"]+)\"[^>]*>$INVOICE_REF', sys.stdin.read()); print(m.group(1) if m else '')" <<< "$INVOICES_PAGE")
    fi

    if [ -n "$INVOICE_KEY" ]; then
        INVOICE_FOUND="true"
        echo "Invoice Key found: $INVOICE_KEY"
        
        # Get the Invoice View Page
        VIEW_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/sales-invoice-view?$INVOICE_KEY" -L)
        
        # Check for attachment
        # Attachments usually appear as links or in a specific div. 
        # We look for the filename in the view page.
        if echo "$VIEW_PAGE" | grep -q "$EXPECTED_FILE"; then
            ATTACHMENT_FOUND="true"
            ATTACHMENT_NAME="$EXPECTED_FILE"
            echo "Attachment '$EXPECTED_FILE' found on invoice page."
        else
            echo "Attachment '$EXPECTED_FILE' NOT found on invoice page."
        fi
    else
        echo "Invoice $INVOICE_REF not found in list."
    fi
fi

# 3. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "invoice_found": $INVOICE_FOUND,
    "attachment_found": $ATTACHMENT_FOUND,
    "attachment_filename": "$ATTACHMENT_NAME",
    "timestamp": $(date +%s)
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result JSON saved."
cat /tmp/task_result.json
echo "=== Export Complete ==="