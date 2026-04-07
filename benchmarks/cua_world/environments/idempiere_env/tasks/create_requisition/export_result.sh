#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting create_requisition results ==="

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Gather Task Context
CLIENT_ID=$(get_gardenworld_client_id)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_REQ_COUNT=$(cat /tmp/initial_requisition_count.txt 2>/dev/null || echo "0")
FINAL_REQ_COUNT=$(idempiere_query "SELECT COUNT(*) FROM m_requisition WHERE ad_client_id=$CLIENT_ID" 2>/dev/null || echo "0")

# 3. Find the target requisition
# We search for the specific description created during the task
TARGET_DESCRIPTION="Seasonal stock replenishment - Summer 2024"

# Query for the specific requisition ID
# We look for the most recently created one matching the description
REQ_ID=$(idempiere_query "SELECT m_requisition_id FROM m_requisition WHERE description='$TARGET_DESCRIPTION' AND ad_client_id=$CLIENT_ID ORDER BY created DESC LIMIT 1" 2>/dev/null || echo "")

# If exact match not found, try partial match to give partial credit
if [ -z "$REQ_ID" ]; then
    REQ_ID=$(idempiere_query "SELECT m_requisition_id FROM m_requisition WHERE LOWER(description) LIKE '%seasonal%stock%replenishment%' AND ad_client_id=$CLIENT_ID ORDER BY created DESC LIMIT 1" 2>/dev/null || echo "")
fi

# 4. Extract details if requisition found
REQ_FOUND="false"
DOC_STATUS=""
DATE_DOC=""
DATE_REQUIRED=""
CREATED_EPOCH="0"
REQ_CLIENT_ID=""
LINE_COUNT="0"
LINES_JSON="[]"

if [ -n "$REQ_ID" ]; then
    REQ_FOUND="true"
    
    # Header details
    DOC_STATUS=$(idempiere_query "SELECT docstatus FROM m_requisition WHERE m_requisition_id=$REQ_ID")
    DATE_DOC=$(idempiere_query "SELECT TO_CHAR(datedoc, 'YYYY-MM-DD') FROM m_requisition WHERE m_requisition_id=$REQ_ID")
    DATE_REQUIRED=$(idempiere_query "SELECT TO_CHAR(daterequired, 'YYYY-MM-DD') FROM m_requisition WHERE m_requisition_id=$REQ_ID")
    CREATED_EPOCH=$(idempiere_query "SELECT EXTRACT(EPOCH FROM created)::bigint FROM m_requisition WHERE m_requisition_id=$REQ_ID")
    REQ_CLIENT_ID=$(idempiere_query "SELECT ad_client_id FROM m_requisition WHERE m_requisition_id=$REQ_ID")
    
    # Line details
    LINE_COUNT=$(idempiere_query "SELECT COUNT(*) FROM m_requisitionline WHERE m_requisition_id=$REQ_ID")
    
    # Construct JSON array of lines (Product Name, Qty)
    # Note: Using a complex query to format as JSON directly from psql is risky due to quoting,
    # so we'll fetch raw rows and construct JSON in bash.
    RAW_LINES=$(idempiere_query "
        SELECT p.name || '|' || rl.qty 
        FROM m_requisitionline rl
        JOIN m_product p ON rl.m_product_id = p.m_product_id
        WHERE rl.m_requisition_id = $REQ_ID
    ")
    
    # Convert raw lines to JSON array
    LINES_JSON="["
    FIRST=1
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            if [ $FIRST -eq 0 ]; then LINES_JSON="$LINES_JSON,"; fi
            P_NAME=$(echo "$line" | cut -d'|' -f1 | sed 's/"/\\"/g')
            P_QTY=$(echo "$line" | cut -d'|' -f2)
            # Remove trailing zeros from decimal qty if present (e.g. 50.0000 -> 50)
            P_QTY=$(echo "$P_QTY" | sed 's/\.0*$//')
            LINES_JSON="$LINES_JSON {\"product\": \"$P_NAME\", \"qty\": $P_QTY}"
            FIRST=0
        fi
    done <<< "$RAW_LINES"
    LINES_JSON="$LINES_JSON ]"
fi

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_epoch": $TASK_START,
    "initial_req_count": $INITIAL_REQ_COUNT,
    "final_req_count": $FINAL_REQ_COUNT,
    "requisition_found": $REQ_FOUND,
    "requisition_details": {
        "id": "${REQ_ID:-null}",
        "doc_status": "${DOC_STATUS:-}",
        "date_doc": "${DATE_DOC:-}",
        "date_required": "${DATE_REQUIRED:-}",
        "created_epoch": ${CREATED_EPOCH:-0},
        "ad_client_id": "${REQ_CLIENT_ID:-}",
        "line_count": ${LINE_COUNT:-0},
        "lines": $LINES_JSON
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 6. Save to final location with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="