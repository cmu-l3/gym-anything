#!/bin/bash
echo "=== Exporting configure_doc_sequence result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Get GardenWorld Client ID
CLIENT_ID=$(get_gardenworld_client_id)
if [ -z "$CLIENT_ID" ]; then
    CLIENT_ID=11
fi

echo "Checking database state for Client ID: $CLIENT_ID"

# 1. Check for the new Sequence
# Returns: id, name, prefix, currentnext, updated_timestamp
SEQ_DATA=$(idempiere_query "
    SELECT ad_sequence_id, name, prefix, currentnext, EXTRACT(EPOCH FROM updated)
    FROM ad_sequence 
    WHERE name='Purchase Order 2025' AND ad_client_id=$CLIENT_ID
" 2>/dev/null)

SEQ_FOUND="false"
SEQ_ID=""
SEQ_NAME=""
SEQ_PREFIX=""
SEQ_NEXT=""
SEQ_UPDATED_TS="0"

if [ -n "$SEQ_DATA" ]; then
    SEQ_FOUND="true"
    SEQ_ID=$(echo "$SEQ_DATA" | cut -d'|' -f1)
    SEQ_NAME=$(echo "$SEQ_DATA" | cut -d'|' -f2)
    SEQ_PREFIX=$(echo "$SEQ_DATA" | cut -d'|' -f3)
    SEQ_NEXT=$(echo "$SEQ_DATA" | cut -d'|' -f4)
    SEQ_UPDATED_TS=$(echo "$SEQ_DATA" | cut -d'|' -f5 | cut -d'.' -f1) # Remove decimals
fi

# 2. Check Document Type Linkage
# Find the Purchase Order doc type and get its linked sequence ID
DOCTYPE_DATA=$(idempiere_query "
    SELECT c_doctype_id, docnosequence_id, EXTRACT(EPOCH FROM updated)
    FROM c_doctype 
    WHERE name='Purchase Order' AND ad_client_id=$CLIENT_ID
" 2>/dev/null)

DOCTYPE_FOUND="false"
LINKED_SEQ_ID=""
DOCTYPE_UPDATED_TS="0"

if [ -n "$DOCTYPE_DATA" ]; then
    DOCTYPE_FOUND="true"
    LINKED_SEQ_ID=$(echo "$DOCTYPE_DATA" | cut -d'|' -f2)
    DOCTYPE_UPDATED_TS=$(echo "$DOCTYPE_DATA" | cut -d'|' -f3 | cut -d'.' -f1)
fi

# 3. Check if app is running
APP_RUNNING=$(pgrep -f firefox > /dev/null && echo "true" || echo "false")

# 4. Take final screenshot
take_screenshot /tmp/task_final.png

# 5. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "sequence_found": $SEQ_FOUND,
    "sequence_details": {
        "id": "$SEQ_ID",
        "name": "$SEQ_NAME",
        "prefix": "$SEQ_PREFIX",
        "current_next": "$SEQ_NEXT",
        "updated_ts": "$SEQ_UPDATED_TS"
    },
    "doctype_found": $DOCTYPE_FOUND,
    "doctype_details": {
        "linked_sequence_id": "$LINKED_SEQ_ID",
        "updated_ts": "$DOCTYPE_UPDATED_TS"
    },
    "app_running": $APP_RUNNING,
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