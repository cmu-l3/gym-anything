#!/bin/bash
set -e

echo "=== Exporting create_quote_with_line_items task result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Get counts
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_QUOTE_COUNT=$(cat /tmp/initial_quote_count.txt 2>/dev/null || echo "0")
CURRENT_QUOTE_COUNT=$(vtiger_count "vtiger_quotes" "1=1" 2>/dev/null || echo "0")

echo "Initial quotes: $INITIAL_QUOTE_COUNT, Current: $CURRENT_QUOTE_COUNT"

# 3. Find the created quote
# Try to find exactly by subject first
QUOTE_ID=$(vtiger_db_query "SELECT quoteid FROM vtiger_quotes WHERE subject='Q-2024-GreenTech-Peripherals' ORDER BY quoteid DESC LIMIT 1" | tr -d '[:space:]')

# If not found, look for fuzzy match on newest quote
if [ -z "$QUOTE_ID" ]; then
    QUOTE_ID=$(vtiger_db_query "SELECT quoteid FROM vtiger_quotes WHERE subject LIKE '%GreenTech%' OR subject LIKE '%Peripheral%' ORDER BY quoteid DESC LIMIT 1" | tr -d '[:space:]')
fi

# Fallback to newest quote created
if [ -z "$QUOTE_ID" ]; then
    QUOTE_ID=$(vtiger_db_query "SELECT quoteid FROM vtiger_quotes ORDER BY quoteid DESC LIMIT 1" | tr -d '[:space:]')
fi

# 4. Extract quote data
QUOTE_EXISTS="false"
QUOTE_SUBJECT=""
QUOTE_VALIDTILL=""
QUOTE_STAGE=""
QUOTE_TOTAL="0"
QUOTE_ORG=""
QUOTE_CREATED_TIME="0"

if [ -n "$QUOTE_ID" ]; then
    QUOTE_EXISTS="true"
    
    # Header data
    HEADER_DATA=$(vtiger_db_query "SELECT q.subject, q.validtill, q.quotestage, q.total, a.accountname, UNIX_TIMESTAMP(c.createdtime) FROM vtiger_quotes q LEFT JOIN vtiger_account a ON q.accountid = a.accountid JOIN vtiger_crmentity c ON q.quoteid = c.crmid WHERE q.quoteid=$QUOTE_ID LIMIT 1")
    
    QUOTE_SUBJECT=$(echo "$HEADER_DATA" | awk -F'\t' '{print $1}')
    QUOTE_VALIDTILL=$(echo "$HEADER_DATA" | awk -F'\t' '{print $2}')
    QUOTE_STAGE=$(echo "$HEADER_DATA" | awk -F'\t' '{print $3}')
    QUOTE_TOTAL=$(echo "$HEADER_DATA" | awk -F'\t' '{print $4}')
    QUOTE_ORG=$(echo "$HEADER_DATA" | awk -F'\t' '{print $5}')
    QUOTE_CREATED_TIME=$(echo "$HEADER_DATA" | awk -F'\t' '{print $6}')

    # Line Items data
    LINE_ITEMS_JSON=$(vtiger_db_query "SELECT CONCAT('[', GROUP_CONCAT(JSON_OBJECT('product_name', p.productname, 'quantity', i.quantity, 'listprice', i.listprice) SEPARATOR ','), ']') FROM vtiger_inventoryproductrel i JOIN vtiger_products p ON i.productid = p.productid WHERE i.id=$QUOTE_ID")
    if [ -z "$LINE_ITEMS_JSON" ] || [ "$LINE_ITEMS_JSON" = "NULL" ]; then
        LINE_ITEMS_JSON="[]"
    fi
else
    LINE_ITEMS_JSON="[]"
fi

# 5. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "initial_quote_count": $INITIAL_QUOTE_COUNT,
    "current_quote_count": $CURRENT_QUOTE_COUNT,
    "quote_exists": $QUOTE_EXISTS,
    "quote_id": "${QUOTE_ID:-}",
    "subject": "$(json_escape "${QUOTE_SUBJECT:-}")",
    "valid_until": "$(json_escape "${QUOTE_VALIDTILL:-}")",
    "quote_stage": "$(json_escape "${QUOTE_STAGE:-}")",
    "total": "${QUOTE_TOTAL:-0}",
    "organization": "$(json_escape "${QUOTE_ORG:-}")",
    "created_time": "${QUOTE_CREATED_TIME:-0}",
    "line_items": $LINE_ITEMS_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Safely copy to /tmp and set permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="