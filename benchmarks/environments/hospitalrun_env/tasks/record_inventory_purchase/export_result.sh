#!/bin/bash
echo "=== Exporting record_inventory_purchase results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Get Task Timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Fetch the Inventory Item Document from CouchDB
ITEM_ID="inventory_p1_GLVLG001"
echo "Fetching item document..."
DOC_JSON=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${ITEM_ID}")

# 4. Check if HospitalRun app is running
APP_RUNNING=$(pgrep -f "node" > /dev/null && echo "true" || echo "false")

# 5. Create Result JSON
# We dump the entire document structure to let the Python verifier parse the 'purchases' array
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "item_document": $DOC_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 6. Move to shared location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="