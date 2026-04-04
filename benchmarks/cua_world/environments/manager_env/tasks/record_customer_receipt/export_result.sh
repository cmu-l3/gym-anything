#!/bin/bash
# Export script for record_customer_receipt task
# Verifies the receipt creation via HTTP API (HTML parsing) and captures evidence

echo "=== Exporting record_customer_receipt result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Prepare for API Verification
COOKIE_FILE="/tmp/mgr_export_cookies.txt"
MANAGER_URL="http://localhost:8080"

# Login
curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" -X POST "$MANAGER_URL/login" -d "Username=administrator" -L -o /dev/null

# Get Business Key
BIZ_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/businesses" -L)
BIZ_KEY=$(python3 -c "import sys, re; m = re.search(r'start\?([^\"&\s]+)[^<]{0,300}Northwind Traders', sys.stdin.read()); print(m.group(1) if m else '')" <<< "$BIZ_PAGE")

FOUND="false"
MATCH_PAYER="false"
MATCH_AMOUNT="false"
MATCH_DATE="false"
MATCH_BANK="false"
CURRENT_COUNT=0
INITIAL_COUNT=$(cat /tmp/initial_receipt_count.txt 2>/dev/null || echo "0")

if [ -n "$BIZ_KEY" ]; then
    # Navigate to business
    curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/start?$BIZ_KEY" -L -o /dev/null
    
    # Fetch Receipts Page
    RECEIPTS_HTML=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/receipts?$BIZ_KEY" -L)
    
    # Count current receipts
    CURRENT_COUNT=$(echo "$RECEIPTS_HTML" | grep -c "View" || echo "0")
    
    # Check for the specific receipt in the HTML table
    # We look for a row containing "Ernst Handel" and "3,500.00"
    # Manager.io tables typically render amounts with commas
    
    # Grep for Ernst Handel
    if echo "$RECEIPTS_HTML" | grep -q "Ernst Handel"; then
        MATCH_PAYER="true"
    fi
    
    # Grep for Amount (3,500.00 or 3500.00)
    if echo "$RECEIPTS_HTML" | grep -E "3,500\.00|3500\.00" | grep -q -v "balance"; then
        MATCH_AMOUNT="true"
    fi
    
    # Grep for Date (15/03/2024 or 2024-03-15 or 15 Mar 2024)
    # Manager.io default date format often depends on browser locale, but usually DD/MM/YYYY or YYYY-MM-DD
    if echo "$RECEIPTS_HTML" | grep -E "15/03/2024|2024-03-15|15 Mar 2024" > /dev/null; then
        MATCH_DATE="true"
    fi
    
    # Grep for Bank Account (Cash on Hand)
    if echo "$RECEIPTS_HTML" | grep -q "Cash on Hand"; then
        MATCH_BANK="true"
    fi
    
    # Combined check: Does a single block/row roughly contain Payer AND Amount?
    # This is a heuristic since proper HTML parsing in bash is hard.
    # We check if the lines containing Ernst Handel also satisfy the amount nearby?
    # Simpler: If both exist in the file, we give good confidence.
    if [ "$MATCH_PAYER" = "true" ] && [ "$MATCH_AMOUNT" = "true" ]; then
        FOUND="true"
    fi
fi

# 3. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "receipt_found": $FOUND,
    "match_payer": $MATCH_PAYER,
    "match_amount": $MATCH_AMOUNT,
    "match_date": $MATCH_DATE,
    "match_bank": $MATCH_BANK,
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "screenshot_path": "/tmp/task_final.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save and permission
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="