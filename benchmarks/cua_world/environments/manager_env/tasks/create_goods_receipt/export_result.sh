#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting Goods Receipt task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Prepare to scrape data
COOKIE_FILE="/tmp/mgr_export_cookies.txt"
MANAGER_URL="http://localhost:8080"

# Login
curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
    -X POST "$MANAGER_URL/login" -d "Username=administrator" -L -o /dev/null

# Get business key
BIZ_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/businesses" -L)
BIZ_KEY=$(echo "$BIZ_PAGE" | python3 -c "
import sys, re
html = sys.stdin.read()
m = re.search(r'start\?([^\"&\s]+)', html)
print(m.group(1) if m else '', end='')
")

# 1. Check if module is enabled
MODULE_ENABLED="false"
BIZ_START=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/start?$BIZ_KEY" -L)
if echo "$BIZ_START" | grep -qi "goods-receipts"; then
    MODULE_ENABLED="true"
fi

# 2. Check for new records
GR_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/goods-receipts?$BIZ_KEY" -L 2>/dev/null)
# Extract links to specific goods receipts
# Regex looks for goods-receipt-view?Key=...
GR_LINKS=$(echo "$GR_PAGE" | grep -oP 'goods-receipt-view\?[^"]+' | head -5)
CURRENT_COUNT=$(echo "$GR_LINKS" | wc -l)
INITIAL_COUNT=$(cat /tmp/manager_task_gr_count_initial 2>/dev/null || echo "0")

RECORD_CREATED="false"
if [ "$CURRENT_COUNT" -gt "0" ] && [ "$CURRENT_COUNT" -gt "$INITIAL_COUNT" ]; then
    RECORD_CREATED="true"
fi

# 3. Extract details from the newest receipt
# We take the first link found (usually the most recent or top of list)
SUPPLIER_FOUND="false"
DATE_FOUND="false"
REF_FOUND="false"
ITEM_CHAI_FOUND="false"
ITEM_CHANG_FOUND="false"
HTML_CONTENT=""

if [ -n "$GR_LINKS" ]; then
    FIRST_GR_URL=$(echo "$GR_LINKS" | head -1)
    # Fetch the detail page
    GR_DETAIL=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/$FIRST_GR_URL" -L)
    HTML_CONTENT="Captured" # Just a flag for JSON

    # Check Supplier
    if echo "$GR_DETAIL" | grep -qi "Exotic Liquids"; then
        SUPPLIER_FOUND="true"
    fi

    # Check Date (2024-07-15) - check various formats
    if echo "$GR_DETAIL" | grep -qiE "15/07/2024|07/15/2024|15.*Jul.*2024|2024-07-15"; then
        DATE_FOUND="true"
    fi

    # Check Reference
    if echo "$GR_DETAIL" | grep -qi "GR-2024-001"; then
        REF_FOUND="true"
    fi

    # Check Line Items (Name and Quantity near each other is hard in raw grep, check presence of both)
    # Chai & 50
    if echo "$GR_DETAIL" | grep -qi "Chai" && echo "$GR_DETAIL" | grep -qE '>50<|50\.00'; then
        ITEM_CHAI_FOUND="true"
    fi
    # Chang & 30
    if echo "$GR_DETAIL" | grep -qi "Chang" && echo "$GR_DETAIL" | grep -qE '>30<|30\.00'; then
        ITEM_CHANG_FOUND="true"
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "module_enabled": $MODULE_ENABLED,
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "record_created": $RECORD_CREATED,
    "details": {
        "supplier_correct": $SUPPLIER_FOUND,
        "date_correct": $DATE_FOUND,
        "ref_correct": $REF_FOUND,
        "chai_correct": $ITEM_CHAI_FOUND,
        "chang_correct": $ITEM_CHANG_FOUND
    },
    "initial_module_state": "$(cat /tmp/manager_task_gr_module_initial 2>/dev/null)",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="