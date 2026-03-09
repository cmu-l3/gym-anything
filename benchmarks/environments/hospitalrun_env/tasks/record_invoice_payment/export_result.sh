#!/bin/bash
echo "=== Exporting record_invoice_payment results ==="

source /workspace/scripts/task_utils.sh

# Record End Time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# IDs
INVOICE_ID="invoice_p1_000042"

# 1. Fetch final invoice state from CouchDB
echo "Fetching invoice data..."
INVOICE_JSON=$(hr_couch_get "$INVOICE_ID")

# 2. Get initial rev to check for modification
INITIAL_REV=$(cat /tmp/initial_invoice_rev.txt 2>/dev/null || echo "")
CURRENT_REV=$(echo "$INVOICE_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('_rev', ''))")

DOC_MODIFIED="false"
if [ "$INITIAL_REV" != "$CURRENT_REV" ] && [ -n "$CURRENT_REV" ]; then
    DOC_MODIFIED="true"
fi

# 3. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 4. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "doc_modified": $DOC_MODIFIED,
    "initial_rev": "$INITIAL_REV",
    "final_rev": "$CURRENT_REV",
    "invoice_data": $INVOICE_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with read permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="