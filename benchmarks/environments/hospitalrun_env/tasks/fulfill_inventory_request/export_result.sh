#!/bin/bash
echo "=== Exporting fulfill_inventory_request result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Extract Data from CouchDB
# We need:
# - Final Status of the request
# - Final Quantity of the inventory item
# - Current _rev of the request (to compare with initial)

echo "Querying CouchDB for final state..."

# Get Request Document
REQUEST_DOC=$(hr_couch_get "inv-request_p1_req001")
FINAL_STATUS=$(echo "$REQUEST_DOC" | python3 -c "import sys, json; doc=json.load(sys.stdin); print(doc.get('data', doc).get('status', 'Unknown'))")
CURRENT_REQUEST_REV=$(echo "$REQUEST_DOC" | python3 -c "import sys, json; print(json.load(sys.stdin).get('_rev', ''))")

# Get Inventory Item Document
ITEM_DOC=$(hr_couch_get "inventory_p1_gauze4x4")
FINAL_QUANTITY=$(echo "$ITEM_DOC" | python3 -c "import sys, json; doc=json.load(sys.stdin); print(doc.get('data', doc).get('quantity', -1))")

# Get Initial Rev
INITIAL_REQUEST_REV=$(cat /tmp/initial_request_rev.txt 2>/dev/null || echo "")

# 3. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "request_status": "$FINAL_STATUS",
    "final_quantity": $FINAL_QUANTITY,
    "initial_rev": "$INITIAL_REQUEST_REV",
    "final_rev": "$CURRENT_REQUEST_REV",
    "rev_changed": $([ "$INITIAL_REQUEST_REV" != "$CURRENT_REQUEST_REV" ] && echo "true" || echo "false"),
    "timestamp": $(date +%s)
}
EOF

# 4. Save to standard location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json