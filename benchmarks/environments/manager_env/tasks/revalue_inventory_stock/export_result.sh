#!/bin/bash
echo "=== Exporting revalue_inventory_stock results ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

MANAGER_URL="http://localhost:8080"
COOKIE_FILE="/tmp/mgr_cookies.txt"
BIZ_KEY=$(cat /tmp/biz_key.txt 2>/dev/null || echo "")

if [ -z "$BIZ_KEY" ]; then
    # Try to recover key
    curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" -X POST "$MANAGER_URL/login" -d "Username=administrator" -L > /dev/null
    BIZ_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/businesses" -L)
    BIZ_KEY=$(python3 -c "import sys, re; m = re.search(r'start\?([^\"&\s]+)[^<]{0,300}Northwind Traders', sys.stdin.read()); print(m.group(1) if m else '')" <<< "$BIZ_PAGE")
fi

# Authenticate just in case
curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" -X POST "$MANAGER_URL/login" -d "Username=administrator" -L > /dev/null

# 1. Check if Module is Enabled
# We check the dashboard or tabs list to see if 'Inventory Revaluations' is present in the sidebar/tabs
IS_MODULE_ENABLED="false"
DASHBOARD_HTML=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/start?$BIZ_KEY" -L)
if echo "$DASHBOARD_HTML" | grep -q "Inventory Revaluations"; then
    IS_MODULE_ENABLED="true"
fi

# 2. Check for the Revaluation Entry
# We fetch the Inventory Revaluations list page
REVAL_LIST_HTML=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "$MANAGER_URL/inventory-revaluations?$BIZ_KEY" -L)

# Parse the HTML using Python to find our specific transaction
# We look for "Aniseed Syrup" and "200" in the table
PYTHON_PARSER=$(cat <<EOF
import sys, re, json

html = sys.stdin.read()
result = {
    "entry_found": False,
    "item_correct": False,
    "amount_correct": False,
    "details": "No entry found"
}

# Simple regex to find rows in the table
# Look for rows containing "Aniseed Syrup"
# Table rows usually look like <tr>...<td>Date</td>...<td>Item</td>...<td>Amount</td>...</tr>
# We accept flexible matching since HTML structure can vary

if "Aniseed Syrup" in html:
    result["item_correct"] = True
    
    # Check for amount 200.00 or 200
    if "200.00" in html or ">200<" in html:
        result["amount_correct"] = True
        result["entry_found"] = True
        result["details"] = "Entry for Aniseed Syrup with amount 200 found"
    else:
        result["details"] = "Item found but amount mismatch"
else:
    result["details"] = "Aniseed Syrup entry not found"

print(json.dumps(result))
EOF
)

VERIFY_JSON=$(echo "$REVAL_LIST_HTML" | python3 -c "$PYTHON_PARSER")

# Combine results
ENTRY_FOUND=$(echo "$VERIFY_JSON" | jq -r .entry_found)
ITEM_CORRECT=$(echo "$VERIFY_JSON" | jq -r .item_correct)
AMOUNT_CORRECT=$(echo "$VERIFY_JSON" | jq -r .amount_correct)

# Check timestamp
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Create result JSON
cat > /tmp/task_result.json << EOF
{
    "module_enabled": $IS_MODULE_ENABLED,
    "entry_found": $ENTRY_FOUND,
    "item_correct": $ITEM_CORRECT,
    "amount_correct": $AMOUNT_CORRECT,
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json