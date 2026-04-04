#!/bin/bash
set -e
echo "=== Exporting add_item_to_purchase_order result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get the Target PO ID
if [ -f /tmp/target_po_id.txt ]; then
    PO_ID=$(cat /tmp/target_po_id.txt)
else
    echo "Error: Target PO ID not found"
    exit 1
fi

if [ -f /tmp/initial_po_rev.txt ]; then
    INITIAL_REV=$(cat /tmp/initial_po_rev.txt)
else
    INITIAL_REV=""
fi

# Fetch the current state of the Purchase Order from CouchDB
echo "Fetching PO document $PO_ID..."
PO_DOC=$(hr_couch_get "$PO_ID")

# Check if app was running
APP_RUNNING="false"
if pgrep -f "firefox" > /dev/null; then
    APP_RUNNING="true"
fi

# Create result JSON
# We embed the full PO doc for the verifier to analyze
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $(cat /tmp/task_start_time.txt 2>/dev/null || echo "0"),
    "timestamp": "$(date -Iseconds)",
    "initial_rev": "$INITIAL_REV",
    "po_id": "$PO_ID",
    "po_document": $PO_DOC,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"