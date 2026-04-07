#!/bin/bash
echo "=== Exporting build_custom_dataset result ==="

source /workspace/scripts/task_utils.sh

# Capture final UI state
take_screenshot /tmp/task_end_screenshot.png

# 1. Query the database for the Dataset Definition
DATASET_DATA=$(oc_query "SELECT dataset_id, name, status_id FROM dataset WHERE name = 'Safety_PK_Analysis' ORDER BY dataset_id DESC LIMIT 1" 2>/dev/null || echo "")

DATASET_FOUND="false"
DATASET_ID=""
DATASET_NAME=""
DATASET_STATUS=""
SELECTED_ITEMS=""
ITEM_COUNT=0

if [ -n "$DATASET_DATA" ]; then
    DATASET_FOUND="true"
    DATASET_ID=$(echo "$DATASET_DATA" | cut -d'|' -f1)
    DATASET_NAME=$(echo "$DATASET_DATA" | cut -d'|' -f2)
    DATASET_STATUS=$(echo "$DATASET_DATA" | cut -d'|' -f3)
    echo "Dataset found: ID=$DATASET_ID, Name=$DATASET_NAME"

    # Fetch the exact clinical items the agent selected into the dataset
    # We query the item names attached to this dataset definition
    ITEM_LIST=$(oc_query "SELECT i.name, i.description FROM dataset_item_status dis JOIN item i ON dis.item_id = i.item_id WHERE dis.dataset_id = $DATASET_ID" 2>/dev/null)
    ITEM_COUNT=$(echo "$ITEM_LIST" | wc -l)
    
    # Flatten item names and descriptions into a comma-separated string for the Python verifier to analyze
    SELECTED_ITEMS=$(echo "$ITEM_LIST" | tr '\n' ',' | tr '|' ' ')
else
    echo "Dataset 'Safety_PK_Analysis' not found in database."
fi

# 2. Check for the exported file in Downloads/Desktop
EXPORT_FILE_EXISTS="false"
EXPORT_FILE_NAME=""
EXPORT_FILE_SIZE=0

EXPORT_FILE=$(find /home/ga/Downloads /home/ga/Desktop -maxdepth 1 -type f \( -name "*.zip" -o -name "*.txt" -o -name "*.tsv" -o -name "*.xls" -o -name "*.csv" \) -newer /tmp/task_start_timestamp 2>/dev/null | head -1)

if [ -n "$EXPORT_FILE" ]; then
    EXPORT_FILE_EXISTS="true"
    EXPORT_FILE_NAME=$(basename "$EXPORT_FILE")
    EXPORT_FILE_SIZE=$(stat -c %s "$EXPORT_FILE" 2>/dev/null || echo "0")
    echo "Export file found: $EXPORT_FILE_NAME ($EXPORT_FILE_SIZE bytes)"
else
    echo "No valid export file found in Downloads or Desktop."
fi

# 3. Get audit logs to ensure GUI usage
AUDIT_LOG_COUNT=$(get_recent_audit_count 120)
AUDIT_BASELINE_COUNT=$(cat /tmp/audit_baseline_count 2>/dev/null || echo "0")

# Write payload for python verifier
TEMP_JSON=$(mktemp /tmp/build_dataset_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "dataset_found": $DATASET_FOUND,
    "dataset_id": "$(json_escape "${DATASET_ID:-}")",
    "dataset_name": "$(json_escape "${DATASET_NAME:-}")",
    "dataset_status": "$(json_escape "${DATASET_STATUS:-}")",
    "item_count": $ITEM_COUNT,
    "selected_items": "$(json_escape "${SELECTED_ITEMS:-}")",
    "export_file_exists": $EXPORT_FILE_EXISTS,
    "export_file_name": "$(json_escape "${EXPORT_FILE_NAME:-}")",
    "export_file_size": $EXPORT_FILE_SIZE,
    "audit_log_count": ${AUDIT_LOG_COUNT:-0},
    "audit_baseline_count": ${AUDIT_BASELINE_COUNT:-0},
    "result_nonce": "$(cat /tmp/result_nonce 2>/dev/null || echo '')"
}
EOF

# Safely copy to standard output location
rm -f /tmp/build_dataset_result.json 2>/dev/null || sudo rm -f /tmp/build_dataset_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/build_dataset_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/build_dataset_result.json
chmod 666 /tmp/build_dataset_result.json 2>/dev/null || sudo chmod 666 /tmp/build_dataset_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="