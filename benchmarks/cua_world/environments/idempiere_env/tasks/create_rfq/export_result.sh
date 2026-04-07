#!/bin/bash
set -e
echo "=== Exporting create_rfq results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Output file
RESULT_JSON="/tmp/task_result.json"
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CLIENT_ID=$(get_gardenworld_client_id)
CLIENT_ID=${CLIENT_ID:-11}

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Query for the RfQ Topic
echo "Checking for RfQ Topic..."
TOPIC_ID=$(idempiere_query "SELECT c_rfq_topic_id FROM c_rfq_topic WHERE name='Spring Furniture Restock' AND ad_client_id=$CLIENT_ID AND isactive='Y' ORDER BY created DESC LIMIT 1" 2>/dev/null || echo "")

TOPIC_FOUND="false"
TOPIC_NAME=""
if [ -n "$TOPIC_ID" ]; then
    TOPIC_FOUND="true"
    TOPIC_NAME="Spring Furniture Restock"
fi

# 3. Query for the RfQ Document linked to this topic
RFQ_FOUND="false"
RFQ_DOCSTATUS=""
RFQ_ID=""
RFQ_CREATED_TS="0"

if [ "$TOPIC_FOUND" = "true" ]; then
    # Get the most recent RfQ for this topic
    RFQ_DATA=$(idempiere_query "SELECT c_rfq_id, docstatus, EXTRACT(EPOCH FROM created) FROM c_rfq WHERE c_rfq_topic_id=$TOPIC_ID AND isactive='Y' ORDER BY created DESC LIMIT 1" 2>/dev/null)
    
    if [ -n "$RFQ_DATA" ]; then
        RFQ_FOUND="true"
        RFQ_ID=$(echo "$RFQ_DATA" | cut -d'|' -f1)
        RFQ_DOCSTATUS=$(echo "$RFQ_DATA" | cut -d'|' -f2)
        RFQ_CREATED_TS_RAW=$(echo "$RFQ_DATA" | cut -d'|' -f3)
        RFQ_CREATED_TS=${RFQ_CREATED_TS_RAW%.*} # Remove decimals
    fi
fi

# 4. Query for RfQ Lines (Product and Qty)
LINE_FOUND="false"
PRODUCT_NAME=""
QTY="0"

if [ "$RFQ_FOUND" = "true" ]; then
    LINE_DATA=$(idempiere_query "SELECT p.name, l.qty FROM c_rfqline l JOIN m_product p ON l.m_product_id = p.m_product_id WHERE l.c_rfq_id=$RFQ_ID AND l.isactive='Y' LIMIT 1" 2>/dev/null)
    
    if [ -n "$LINE_DATA" ]; then
        LINE_FOUND="true"
        PRODUCT_NAME=$(echo "$LINE_DATA" | cut -d'|' -f1)
        QTY=$(echo "$LINE_DATA" | cut -d'|' -f2)
    fi
fi

# 5. Query for Subscribers (RfQ Responses)
SUBSCRIBER_COUNT="0"
SUBSCRIBERS_LIST=""

if [ "$RFQ_FOUND" = "true" ]; then
    SUBSCRIBER_COUNT=$(idempiere_query "SELECT COUNT(*) FROM c_rfqresponse WHERE c_rfq_id=$RFQ_ID AND isactive='Y'" 2>/dev/null || echo "0")
    
    # Get names of subscribers (Business Partners)
    SUBSCRIBERS_LIST=$(idempiere_query "SELECT bp.name FROM c_rfqresponse r JOIN c_bpartner bp ON r.c_bpartner_id = bp.c_bpartner_id WHERE r.c_rfq_id=$RFQ_ID AND r.isactive='Y'" 2>/dev/null | tr '\n' ',' || echo "")
fi

# 6. Check timestamps (Anti-gaming)
CREATED_DURING_TASK="false"
if [ "$RFQ_CREATED_TS" -gt "$TASK_START_TIME" ]; then
    CREATED_DURING_TASK="true"
fi

# 7. Construct JSON
# Note: Using python to construct JSON handles escaping safely
python3 -c "
import json
import sys

data = {
    'topic_found': $TOPIC_FOUND,
    'topic_name': '$TOPIC_NAME',
    'rfq_found': $RFQ_FOUND,
    'rfq_docstatus': '$RFQ_DOCSTATUS',
    'line_found': $LINE_FOUND,
    'product_name': '''$PRODUCT_NAME''',
    'qty': $QTY,
    'subscriber_count': int('$SUBSCRIBER_COUNT'),
    'subscribers_list': '''$SUBSCRIBERS_LIST''',
    'created_during_task': $CREATED_DURING_TASK,
    'timestamp': '$(date -Iseconds)'
}

with open('$RESULT_JSON', 'w') as f:
    json.dump(data, f, indent=2)
"

# Set permissions
chmod 666 "$RESULT_JSON"

echo "Result exported to $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export complete ==="