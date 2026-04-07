#!/bin/bash
set -e
echo "=== Exporting create_customer_shipment results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# ------------------------------------------------------------------
# Gather Data from Database
# ------------------------------------------------------------------

CLIENT_ID=$(get_gardenworld_client_id)
TASK_START_TS=$(date -d @"$TASK_START" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "2000-01-01 00:00:00")

echo "Searching for shipments created after $TASK_START_TS..."

# 1. Find the most recently created shipment for GardenWorld since task start
# We look for a Sales Transaction (IsSOTrx='Y') in M_InOut
SHIPMENT_ID=$(idempiere_query "
    SELECT m_inout_id 
    FROM m_inout 
    WHERE ad_client_id=$CLIENT_ID 
      AND issotrx='Y' 
      AND created >= '$TASK_START_TS' 
    ORDER BY created DESC 
    LIMIT 1
" 2>/dev/null || echo "")

echo "Found Shipment ID: $SHIPMENT_ID"

# Initialize result variables
SHIPMENT_FOUND="false"
BP_NAME=""
DOC_STATUS=""
LINES_JSON="[]"
CREATED_TS=""

if [ -n "$SHIPMENT_ID" ] && [ "$SHIPMENT_ID" != "" ]; then
    SHIPMENT_FOUND="true"

    # Get Business Partner Name
    BP_NAME=$(idempiere_query "
        SELECT bp.name 
        FROM m_inout s 
        JOIN c_bpartner bp ON s.c_bpartner_id = bp.c_bpartner_id 
        WHERE s.m_inout_id=$SHIPMENT_ID
    ")
    
    # Get Document Status (CO=Completed, DR=Draft, etc)
    DOC_STATUS=$(idempiere_query "SELECT docstatus FROM m_inout WHERE m_inout_id=$SHIPMENT_ID")
    
    # Get Creation Timestamp (for verification)
    CREATED_TS=$(idempiere_query "SELECT created FROM m_inout WHERE m_inout_id=$SHIPMENT_ID")

    # Get Lines (Product Name and Quantity)
    # We use a python one-liner to format the SQL output as JSON because bash is messy with lists
    # SQL output format: "Product Name|Qty" per line
    LINES_RAW=$(idempiere_query "
        SELECT p.name || '|' || l.movementqty
        FROM m_inoutline l
        JOIN m_product p ON l.m_product_id = p.m_product_id
        WHERE l.m_inout_id=$SHIPMENT_ID
    ")
    
    # Convert raw lines to JSON array using Python
    LINES_JSON=$(python3 -c "
import sys, json
lines = []
raw = '''$LINES_RAW'''
for row in raw.strip().split('\n'):
    if '|' in row:
        p, q = row.split('|')
        try:
            qty = float(q)
        except:
            qty = 0
        lines.append({'product_name': p.strip(), 'quantity': qty})
print(json.dumps(lines))
" 2>/dev/null || echo "[]")

fi

# ------------------------------------------------------------------
# Generate Result JSON
# ------------------------------------------------------------------

# Use a temp file for JSON generation
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "shipment_found": $SHIPMENT_FOUND,
    "shipment_id": "${SHIPMENT_ID:-0}",
    "bp_name": "${BP_NAME:-}",
    "doc_status": "${DOC_STATUS:-}",
    "created_ts": "${CREATED_TS:-}",
    "lines": $LINES_JSON,
    "screenshot_path": "/tmp/task_final_state.png"
}
EOF

# Move to final location with permissive permissions
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="