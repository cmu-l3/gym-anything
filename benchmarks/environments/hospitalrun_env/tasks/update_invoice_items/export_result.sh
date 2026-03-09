#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
INITIAL_REV=$(cat /tmp/initial_invoice_rev.txt 2>/dev/null || echo "")

# 1. Fetch the invoice document from CouchDB
echo "Fetching invoice data..."
INVOICE_DOC=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/invoice_inv_2024_001")

# 2. Analyze the document
# Extract key fields for the verifier using python
# We extract _rev, lineItems, total, and status
PARSED_RESULT=$(echo "$INVOICE_DOC" | python3 -c "
import sys, json
try:
    doc = json.load(sys.stdin)
    data = doc.get('data', doc) # Handle nested data wrapper if present (HR structure varies)
    
    # Check revision
    current_rev = doc.get('_rev', '')
    initial_rev = '$INITIAL_REV'
    modified = current_rev != initial_rev and initial_rev != ''
    
    # Get line items
    items = data.get('lineItems', [])
    item_names = [i.get('name', '') for i in items]
    
    # Get total
    total = data.get('total', 0)
    
    result = {
        'exists': '_id' in doc and 'error' not in doc,
        'modified': modified,
        'current_rev': current_rev,
        'item_count': len(items),
        'item_names': item_names,
        'total': total,
        'status': data.get('status', 'Unknown')
    }
    print(json.dumps(result))
except Exception as e:
    print(json.dumps({'error': str(e), 'exists': False}))
")

# 3. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 4. Check App State
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# 5. Compile Final JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "invoice_data": $PARSED_RESULT
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json