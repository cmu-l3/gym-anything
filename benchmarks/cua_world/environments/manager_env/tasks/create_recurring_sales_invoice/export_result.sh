#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting task results ==="

MANAGER_URL="http://localhost:8080"
COOKIE_FILE="/tmp/mgr_export_cookies.txt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Login to API to inspect state
curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
    -X POST "$MANAGER_URL/login" \
    -d "Username=administrator" -L -o /dev/null 2>/dev/null

# Get Business Key
BIZ_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
    "$MANAGER_URL/businesses" -L 2>/dev/null)
BIZ_KEY=$(python3 -c "
import re, sys
html = sys.stdin.read()
m = re.search(r'start\?([^\"&\s]+)[^<]{0,300}Northwind Traders', html)
if not m: m = re.search(r'start\?([^\"&\s]+)', html)
print(m.group(1) if m else '', end='')
" <<< "$BIZ_PAGE")

# Inspect Summary Page for "Recurring Sales Invoices" tab
SUMMARY_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
    "$MANAGER_URL/start?$BIZ_KEY" -L 2>/dev/null)

TAB_ENABLED="false"
if echo "$SUMMARY_PAGE" | grep -qi "recurring-sales-invoices"; then
    TAB_ENABLED="true"
fi

# Inspect Recurring Sales Invoices List
INVOICE_FOUND="false"
CUSTOMER_MATCH="false"
AMOUNT_MATCH="false"
DESC_MATCH="false"
INTERVAL_MATCH="false"
RAW_DETAILS=""

if [ "$TAB_ENABLED" = "true" ]; then
    LIST_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
        "$MANAGER_URL/recurring-sales-invoices?$BIZ_KEY" -L 2>/dev/null)
    
    # Extract link to the most recent invoice (if any)
    # Look for href containing recurring-sales-invoice?Key=...
    INVOICE_URL=$(echo "$LIST_PAGE" | grep -o 'href="recurring-sales-invoice?[^"]*"' | head -1 | cut -d'"' -f2)
    
    if [ -n "$INVOICE_URL" ]; then
        INVOICE_FOUND="true"
        
        # Get Invoice Details
        DETAIL_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
            "$MANAGER_URL/$INVOICE_URL" -L 2>/dev/null)
        
        # Save raw details for debug/verification
        RAW_DETAILS=$(echo "$DETAIL_PAGE" | head -c 2000 | tr -d '\n' | sed 's/"/\\"/g')

        # Check fields
        if echo "$DETAIL_PAGE" | grep -qi "Alfreds Futterkiste"; then
            CUSTOMER_MATCH="true"
        fi
        
        if echo "$DETAIL_PAGE" | grep -qE "150\.00|150,00"; then
            AMOUNT_MATCH="true"
        fi
        
        if echo "$DETAIL_PAGE" | grep -qiE "Gourmet|Food|Box|Subscription"; then
            DESC_MATCH="true"
        fi
        
        # Check for "Monthly" or "1 Month" or "Month" in recurrence info
        # The view page often shows "Every month" or similar text
        if echo "$DETAIL_PAGE" | grep -qiE "Every.*Month|Monthly"; then
            INTERVAL_MATCH="true"
        fi
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "tab_enabled": $TAB_ENABLED,
    "invoice_found": $INVOICE_FOUND,
    "customer_match": $CUSTOMER_MATCH,
    "amount_match": $AMOUNT_MATCH,
    "description_match": $DESC_MATCH,
    "interval_match": $INTERVAL_MATCH,
    "debug_details": "$RAW_DETAILS"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"