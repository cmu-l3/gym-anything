#!/bin/bash
set -e
echo "=== Exporting Material Receipt Task Results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Capture final state screenshot
take_screenshot /tmp/task_final.png

# Load task context
CLIENT_ID=$(get_gardenworld_client_id)
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_receipt_count.txt 2>/dev/null || echo "0")
CURRENT_COUNT=$(idempiere_query "SELECT COUNT(*) FROM m_inout WHERE ad_client_id=$CLIENT_ID AND issotrx='N'" 2>/dev/null || echo "0")

echo "Receipt Count: Initial=$INITIAL_COUNT, Current=$CURRENT_COUNT"

# Find the most recently created Material Receipt
# We look for receipts created after task start time
# Note: PostgreSQL timestamp extraction
# We select the one with the highest ID to be safe
LATEST_RECEIPT_JSON="{}"

# Check if any new receipt exists
if [ "$CURRENT_COUNT" -gt "$INITIAL_COUNT" ]; then
    echo "Found new receipt(s). Querying details..."

    # Complex query to construct JSON object directly from PostgreSQL would be ideal,
    # but for compatibility we'll fetch fields and construct JSON in bash.

    # Fetch Header Details
    # m_inout_id, documentno, description, docstatus, business_partner_name, created_epoch
    HEADER_DATA=$(idempiere_query "
        SELECT 
            io.m_inout_id,
            io.documentno,
            COALESCE(io.description, ''),
            io.docstatus,
            bp.name,
            EXTRACT(EPOCH FROM io.created)::bigint
        FROM m_inout io
        JOIN c_bpartner bp ON io.c_bpartner_id = bp.c_bpartner_id
        WHERE io.ad_client_id=$CLIENT_ID 
          AND io.issotrx='N'
        ORDER BY io.created DESC, io.m_inout_id DESC
        LIMIT 1
    ")

    if [ -n "$HEADER_DATA" ]; then
        # Parse pipe-separated values (default psql output in idempiere_query is usually pipe or aligned)
        # task_utils.sh idempiere_query uses -t -A, which implies pipe separator by default for some versions, 
        # but let's be safe and assume standard output format from the helper.
        # actually task_utils.sh: psql ... -t -A -c ... 
        # -A unaligned, -t tuples only. Separator is '|'.
        
        RECEIPT_ID=$(echo "$HEADER_DATA" | cut -d'|' -f1)
        DOC_NO=$(echo "$HEADER_DATA" | cut -d'|' -f2)
        DESC=$(echo "$HEADER_DATA" | cut -d'|' -f3)
        STATUS=$(echo "$HEADER_DATA" | cut -d'|' -f4)
        BP_NAME=$(echo "$HEADER_DATA" | cut -d'|' -f5)
        CREATED_TIME=$(echo "$HEADER_DATA" | cut -d'|' -f6)

        echo "  Latest Receipt: ID=$RECEIPT_ID, DocNo=$DOC_NO, Status=$STATUS, BP=$BP_NAME"

        # Fetch Lines
        # product_name, movementqty
        LINES_DATA=$(idempiere_query "
            SELECT 
                p.name,
                iol.movementqty
            FROM m_inoutline iol
            JOIN m_product p ON iol.m_product_id = p.m_product_id
            WHERE iol.m_inout_id=$RECEIPT_ID
            ORDER BY iol.line
        ")
        
        # Convert lines to JSON array
        LINES_JSON="[]"
        if [ -n "$LINES_DATA" ]; then
            # Process each line
            LINES_JSON="["
            while IFS='|' read -r P_NAME P_QTY; do
                LINES_JSON="${LINES_JSON}{\"product\": \"$P_NAME\", \"qty\": $P_QTY},"
            done <<< "$LINES_DATA"
            # Remove trailing comma and close array
            LINES_JSON="${LINES_JSON%,}]"
        fi

        # Construct full JSON
        # Escape quotes in strings
        DESC_ESCAPED=$(echo "$DESC" | sed 's/"/\\"/g')
        BP_ESCAPED=$(echo "$BP_NAME" | sed 's/"/\\"/g')
        
        LATEST_RECEIPT_JSON="{
            \"exists\": true,
            \"id\": $RECEIPT_ID,
            \"document_no\": \"$DOC_NO\",
            \"description\": \"$DESC_ESCAPED\",
            \"doc_status\": \"$STATUS\",
            \"vendor_name\": \"$BP_ESCAPED\",
            \"created_time\": $CREATED_TIME,
            \"lines\": $LINES_JSON
        }"
    else
        LATEST_RECEIPT_JSON="{\"exists\": false}"
    fi
else
    LATEST_RECEIPT_JSON="{\"exists\": false}"
fi

# Create final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START_TIME,
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "latest_receipt": $LATEST_RECEIPT_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with proper permissions
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="