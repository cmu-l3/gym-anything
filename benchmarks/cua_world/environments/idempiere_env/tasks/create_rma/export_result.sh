#!/bin/bash
echo "=== Exporting create_rma task results ==="

source /workspace/scripts/task_utils.sh

# Record task end info
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_RMA_COUNT=$(cat /tmp/initial_rma_count.txt 2>/dev/null || echo "0")
CLIENT_ID=$(get_gardenworld_client_id)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query for RMAs created during the task
# We look for RMAs created after task start OR just new records (ID > max ID at start would be ideal, 
# but simply checking created timestamp or count difference is robust enough for this env)
echo "Querying new RMA records..."

# Get details of the most recently created RMA for C&W Construction
# We use a complex query to get Header info + Line count + Referenced Shipment info
SQL_QUERY="
SELECT 
    r.m_rma_id,
    r.documentno,
    r.docstatus,
    r.description,
    bp.name as bp_name,
    io.documentno as shipment_doc,
    (SELECT COUNT(*) FROM m_rmaline l WHERE l.m_rma_id = r.m_rma_id) as line_count,
    r.created
FROM m_rma r
JOIN c_bpartner bp ON r.c_bpartner_id = bp.c_bpartner_id
LEFT JOIN m_inout io ON r.m_inout_id = io.m_inout_id
WHERE r.ad_client_id = $CLIENT_ID
  AND bp.name LIKE 'C&W Construction%'
ORDER BY r.created DESC
LIMIT 1
"

# Execute Query
RMA_DATA=$(idempiere_query "$SQL_QUERY")

# Parse Result (Postgres output format depends on flags in idempiere_query, usually pipe or distinct sep)
# The utility uses -A (unaligned) -t (tuples only), separator is usually pipe '|'
# Structure: ID|DocNo|Status|Desc|BPName|ShipmentDoc|LineCount|Created

RMA_FOUND="false"
if [ -n "$RMA_DATA" ]; then
    RMA_FOUND="true"
    IFS='|' read -r RMA_ID DOC_NO DOC_STATUS DESC BP_NAME SHIPMENT_DOC LINE_COUNT CREATED <<< "$RMA_DATA"
fi

# Get current total count
CURRENT_RMA_COUNT=$(idempiere_query "SELECT COUNT(*) FROM m_rma WHERE ad_client_id=$CLIENT_ID" 2>/dev/null || echo "0")

# Check timestamps to ensure it wasn't pre-existing (approximate check)
# In a real DB, 'created' is a timestamp. We can check if count increased.
IS_NEW="false"
if [ "$CURRENT_RMA_COUNT" -gt "$INITIAL_RMA_COUNT" ]; then
    IS_NEW="true"
fi

# Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "rma_found": $RMA_FOUND,
    "is_new_record": $IS_NEW,
    "rma_details": {
        "id": "${RMA_ID:-}",
        "document_no": "${DOC_NO:-}",
        "doc_status": "${DOC_STATUS:-}",
        "description": "${DESC:-}",
        "bp_name": "${BP_NAME:-}",
        "shipment_ref": "${SHIPMENT_DOC:-}",
        "line_count": ${LINE_COUNT:-0},
        "created_ts": "${CREATED:-}"
    },
    "initial_count": $INITIAL_RMA_COUNT,
    "current_count": $CURRENT_RMA_COUNT
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="