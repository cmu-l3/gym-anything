#!/bin/bash
echo "=== Exporting record_net_deposit_receipt results ==="

source /workspace/scripts/task_utils.sh

# Record task end
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# ---------------------------------------------------------------------------
# Extract Data via API for Verification
# ---------------------------------------------------------------------------
MANAGER_URL="http://localhost:8080"
COOKIE_FILE="/tmp/mgr_setup_cookies.txt"

# Login/Refresh session
curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" -X POST "$MANAGER_URL/login" -d "Username=administrator" -L -o /dev/null

# Get Business Key
BIZ_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/businesses" -L)
BIZ_KEY=$(echo "$BIZ_PAGE" | grep -o 'start?[^"]*' | head -1 | cut -d? -f2)

# 1. Check Invoice Status (Is it paid?)
# We fetch the invoices list and look for INV-STRIPE-001
# In Manager, paid invoices often show Balance Due as 0.00
INV_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/sales-invoices?$BIZ_KEY" -L)
INV_ROW=$(echo "$INV_PAGE" | grep -A 10 "INV-STRIPE-001")

# Extract Balance Due from the row (rough HTML parsing)
# Looking for the column that typically holds balance.
# Or better: check if the status badge says "Paid in full" if available, or just parse the number.
# Using a python snippet to parse the specific row is safer.
INV_STATUS_JSON=$(python3 -c "
import sys, re
html = sys.stdin.read()
# Find the row with INV-STRIPE-001
row_match = re.search(r'<tr[^>]*>.*?INV-STRIPE-001.*?</tr>', html, re.DOTALL)
if row_match:
    row = row_match.group(0)
    # Check for balance due. Typically the last numeric column.
    # If Paid in full, it might not show a balance or show 0.00
    cols = re.findall(r'<td[^>]*>(.*?)</td>', row, re.DOTALL)
    if cols:
        print(row)
" <<< "$INV_PAGE")

# 2. Check for the Receipt
# We look for a receipt created today with total 485.00
# Fetch receipts list
RECEIPTS_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/receipts?$BIZ_KEY" -L)

# We need to find a receipt that links to the invoice or matches the amount 485.00
# Let's find the receipt link to inspect details
RECEIPT_URL=$(echo "$RECEIPTS_PAGE" | grep "485.00" | grep -o 'view-receipt?[^"]*' | head -1)

RECEIPT_DETAILS=""
RECEIPT_LINES=""
TOTAL_AMOUNT="0"

if [ -n "$RECEIPT_URL" ]; then
    # Fetch receipt details
    RECEIPT_HTML=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/$RECEIPT_URL" -L)
    
    # Check if it contains the invoice reference
    if echo "$RECEIPT_HTML" | grep -q "INV-STRIPE-001"; then
        MATCH_INVOICE="true"
    else
        MATCH_INVOICE="false"
    fi
    
    # Check if it contains the expense account
    if echo "$RECEIPT_HTML" | grep -q "Bank Service Charges"; then
        MATCH_EXPENSE="true"
    else
        MATCH_EXPENSE="false"
    fi
    
    TOTAL_AMOUNT="485.00"
else
    MATCH_INVOICE="false"
    MATCH_EXPENSE="false"
fi

# 3. Check Receipt Count Change
INITIAL_COUNT=$(cat /tmp/initial_receipt_count.txt 2>/dev/null || echo "0")
CURRENT_COUNT=$(echo "$RECEIPTS_PAGE" | grep -c "View")
NEW_RECEIPTS=$((CURRENT_COUNT - INITIAL_COUNT))

# Create JSON Result
TEMP_JSON=$(mktemp /tmp/net_deposit_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "invoice_status_raw": $(echo "$INV_STATUS_JSON" | jq -R -s '.'), 
    "receipt_found": $([ -n "$RECEIPT_URL" ] && echo "true" || echo "false"),
    "receipt_total_correct": $([ "$TOTAL_AMOUNT" == "485.00" ] && echo "true" || echo "false"),
    "receipt_links_invoice": $MATCH_INVOICE,
    "receipt_includes_fee": $MATCH_EXPENSE,
    "new_receipts_count": $NEW_RECEIPTS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save result
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"