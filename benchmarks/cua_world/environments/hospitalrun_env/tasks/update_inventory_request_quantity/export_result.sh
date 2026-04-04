#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Docs we care about
REQ_ID="inv_req_masks_001"
INITIAL_REV=$(cat /tmp/initial_req_rev.txt 2>/dev/null || echo "")

# 1. Fetch the current state of the request document from CouchDB
echo "Fetching final document state..."
DOC_JSON=$(hr_couch_get "$REQ_ID")

# 2. Extract key fields using Python
# We extract: current _rev, quantity, status, and the linked item
# Also checking if the item name is resolved in the doc (sometimes it is)
STATE_JSON=$(echo "$DOC_JSON" | python3 -c "
import sys, json
try:
    doc = json.load(sys.stdin)
    data = doc.get('data', doc) # Handle wrapped or unwrapped data
    print(json.dumps({
        'doc_exists': '_id' in doc or 'id' in doc,
        'current_rev': doc.get('_rev', ''),
        'quantity': data.get('quantity'),
        'status': data.get('status'),
        'inventory_item_id': data.get('inventoryItem'),
        'initial_rev': '$INITIAL_REV'
    }))
except Exception as e:
    print(json.dumps({'error': str(e), 'doc_exists': False}))
")

# 3. Take final screenshot
take_screenshot /tmp/task_final.png

# 4. Save result to a file readable by the verifier
# Using a temp file first to ensure atomic write/permissions
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
echo "$STATE_JSON" > "$TEMP_JSON"

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json