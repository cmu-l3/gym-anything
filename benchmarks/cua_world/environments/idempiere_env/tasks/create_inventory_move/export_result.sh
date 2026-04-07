#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting create_inventory_move result ==="

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Retrieve initial state and timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_START_TS=$(date -d @"$TASK_START" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "2000-01-01 00:00:00")
INITIAL_COUNT=$(cat /tmp/initial_movement_count.txt 2>/dev/null || echo "0")
CLIENT_ID=$(get_gardenworld_client_id)

echo "Task Start TS: $TASK_START_TS"

# 3. Find the created movement document
# Look for a movement created after task start, ideally with "Azalea" in description, or just the latest one
MOVEMENT_ID=$(idempiere_query "SELECT m_movement_id FROM m_movement WHERE ad_client_id=$CLIENT_ID AND created >= '$TASK_START_TS' ORDER BY created DESC LIMIT 1" 2>/dev/null || echo "")

echo "Found Movement ID: $MOVEMENT_ID"

# 4. Extract details if document found
DOC_EXISTS="false"
DOC_STATUS=""
DESCRIPTION=""
LINE_COUNT=0
PRODUCT_NAME=""
QTY=0
SRC_LOCATOR_ID=""
TGT_LOCATOR_ID=""
WAREHOUSE_ID=""

if [ -n "$MOVEMENT_ID" ] && [ "$MOVEMENT_ID" != "" ]; then
    DOC_EXISTS="true"
    
    # Header details
    DOC_STATUS=$(idempiere_query "SELECT docstatus FROM m_movement WHERE m_movement_id=$MOVEMENT_ID")
    DESCRIPTION=$(idempiere_query "SELECT description FROM m_movement WHERE m_movement_id=$MOVEMENT_ID")
    
    # Line details (checking the first line)
    LINE_COUNT=$(idempiere_query "SELECT COUNT(*) FROM m_movementline WHERE m_movement_id=$MOVEMENT_ID")
    
    if [ "$LINE_COUNT" -gt 0 ]; then
        PRODUCT_NAME=$(idempiere_query "SELECT p.name FROM m_movementline ml JOIN m_product p ON ml.m_product_id=p.m_product_id WHERE ml.m_movement_id=$MOVEMENT_ID LIMIT 1")
        QTY=$(idempiere_query "SELECT movementqty FROM m_movementline WHERE m_movement_id=$MOVEMENT_ID LIMIT 1")
        SRC_LOCATOR_ID=$(idempiere_query "SELECT m_locator_id FROM m_movementline WHERE m_movement_id=$MOVEMENT_ID LIMIT 1")
        TGT_LOCATOR_ID=$(idempiere_query "SELECT m_locatorto_id FROM m_movementline WHERE m_movement_id=$MOVEMENT_ID LIMIT 1")
        
        # Verify Warehouse from locator
        if [ -n "$SRC_LOCATOR_ID" ]; then
            WAREHOUSE_ID=$(idempiere_query "SELECT m_warehouse_id FROM m_locator WHERE m_locator_id=$SRC_LOCATOR_ID")
        fi
    fi
fi

# 5. Check total count (anti-gaming)
FINAL_COUNT=$(idempiere_query "SELECT COUNT(*) FROM m_movement WHERE ad_client_id=$CLIENT_ID" 2>/dev/null || echo "0")
COUNT_DELTA=$((FINAL_COUNT - INITIAL_COUNT))

# 6. Create JSON result
# Use a temp file to avoid permission issues
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

# Escape strings for JSON
SAFE_DESC=$(echo "$DESCRIPTION" | sed 's/"/\\"/g' | sed 's/
//g')
SAFE_PROD=$(echo "$PRODUCT_NAME" | sed 's/"/\\"/g')

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "doc_exists": $DOC_EXISTS,
    "movement_id": "${MOVEMENT_ID:-0}",
    "doc_status": "${DOC_STATUS:-}",
    "description": "${SAFE_DESC:-}",
    "line_count": ${LINE_COUNT:-0},
    "product_name": "${SAFE_PROD:-}",
    "quantity": ${QTY:-0},
    "src_locator_id": "${SRC_LOCATOR_ID:-}",
    "tgt_locator_id": "${TGT_LOCATOR_ID:-}",
    "warehouse_id": "${WAREHOUSE_ID:-}",
    "count_delta": $COUNT_DELTA,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="