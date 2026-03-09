#!/bin/bash
# Export script for link_related_requests task

echo "=== Exporting Link Related Requests Result ==="
source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Get Task Info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Read Request IDs
if [ -f /tmp/task_request_ids.txt ]; then
    REQ_A=$(head -1 /tmp/task_request_ids.txt)
    REQ_B=$(tail -1 /tmp/task_request_ids.txt)
else
    REQ_A="0"
    REQ_B="0"
fi

echo "Checking link between Request $REQ_A and $REQ_B..."

# 4. Query Database for Link
# Table: WorkOrderToWorkOrder maps relationships.
# We check both directions (A->B or B->A).
LINK_QUERY="SELECT count(*) FROM WorkOrderToWorkOrder WHERE (WORKORDERID_LEFT = $REQ_A AND WORKORDERID_RIGHT = $REQ_B) OR (WORKORDERID_LEFT = $REQ_B AND WORKORDERID_RIGHT = $REQ_A);"
LINK_COUNT=$(sdp_db_exec "$LINK_QUERY")

# Also check if a record exists with a creation time (if available in link table)
# WorkOrderToWorkOrder usually just has IDs and relationship ID.
# We can check 'history' or 'system_log' if strict timing is needed, but presence is usually enough if requests were fresh.

# Check if requests still exist (sanity check)
REQ_A_EXISTS=$(sdp_db_exec "SELECT count(*) FROM WorkOrder WHERE WORKORDERID = $REQ_A;")

# 5. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "request_a_id": "$REQ_A",
    "request_b_id": "$REQ_B",
    "link_count": ${LINK_COUNT:-0},
    "requests_exist": ${REQ_A_EXISTS:-0},
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported:"
cat /tmp/task_result.json
echo "=== Export Complete ==="