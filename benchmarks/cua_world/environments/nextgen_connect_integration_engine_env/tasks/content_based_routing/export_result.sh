#!/bin/bash
echo "=== Exporting Content Based Routing Result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Gather Basic State
INITIAL_COUNT=$(cat /tmp/initial_channel_count.txt 2>/dev/null || echo "0")
CURRENT_COUNT=$(get_channel_count)
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Find the Channel
CHANNEL_INFO=$(query_postgres "SELECT id, name FROM channel WHERE LOWER(name) LIKE '%router%' OR LOWER(name) LIKE '%hl7%' LIMIT 1;" 2>/dev/null || true)
CHANNEL_ID=$(echo "$CHANNEL_INFO" | cut -d'|' -f1)
CHANNEL_NAME=$(echo "$CHANNEL_INFO" | cut -d'|' -f2)

# 4. Check Deployment Status
CHANNEL_STATUS="UNKNOWN"
if [ -n "$CHANNEL_ID" ]; then
    CHANNEL_STATUS=$(get_channel_status_api "$CHANNEL_ID")
fi

# 5. Extract Configuration (Port & Destinations)
LISTEN_PORT=""
DESTINATION_COUNT=0
if [ -n "$CHANNEL_ID" ]; then
    CHANNEL_XML=$(query_postgres "SELECT channel FROM channel WHERE id='$CHANNEL_ID';" 2>/dev/null || true)
    
    # Get Port
    LISTEN_PORT=$(echo "$CHANNEL_XML" | python3 -c "import sys, re; xml=sys.stdin.read(); m=re.search(r'<port>(\d+)</port>', xml); print(m.group(1) if m else '')" 2>/dev/null)
    
    # Count Destinations
    DESTINATION_COUNT=$(echo "$CHANNEL_XML" | grep -c "<transportName>File Writer</transportName>" || echo "0")
fi

# 6. ACTIVE VERIFICATION: Send Test Messages & Verify Routing
# We will send 3 messages and check where they land.
# We clear the output dirs first (if they exist) to be sure we are measuring THIS run.
# Note: Agent might have created them, but we want to verify logic.
rm -rf /tmp/output/adt/* /tmp/output/orm/* /tmp/output/oru/* 2>/dev/null || true
mkdir -p /tmp/output/adt /tmp/output/orm /tmp/output/oru 2>/dev/null || true
chmod 777 /tmp/output/adt /tmp/output/orm /tmp/output/oru 2>/dev/null || true

echo "Sending Test Messages to port $LISTEN_PORT..."

if [ -n "$LISTEN_PORT" ]; then
    # Helper to send MLLP
    send_mllp() {
        local file=$1
        local port=$2
        # Wrap in MLLP (VT ... FS CR)
        (printf '\x0b'; cat "$file"; printf '\x1c\x0d') | nc -w 2 localhost "$port"
        sleep 1
    }

    # Send ADT
    send_mllp "/home/ga/sample_adt.hl7" "$LISTEN_PORT"
    # Send ORM
    send_mllp "/home/ga/sample_orm.hl7" "$LISTEN_PORT"
    # Send ORU
    send_mllp "/home/ga/sample_oru.hl7" "$LISTEN_PORT"
    
    # Allow processing time
    sleep 5
fi

# 7. Verify Output Content
# Check ADT Folder
ADT_SUCCESS="false"
ADT_CONTAMINATION="false"
if [ -n "$(ls -A /tmp/output/adt/ 2>/dev/null)" ]; then
    # Check if files contain ADT
    if grep -q "ADT" /tmp/output/adt/* 2>/dev/null; then ADT_SUCCESS="true"; fi
    # Check for wrong types
    if grep -q "ORM\|ORU" /tmp/output/adt/* 2>/dev/null; then ADT_CONTAMINATION="true"; fi
fi

# Check ORM Folder
ORM_SUCCESS="false"
ORM_CONTAMINATION="false"
if [ -n "$(ls -A /tmp/output/orm/ 2>/dev/null)" ]; then
    if grep -q "ORM" /tmp/output/orm/* 2>/dev/null; then ORM_SUCCESS="true"; fi
    if grep -q "ADT\|ORU" /tmp/output/orm/* 2>/dev/null; then ORM_CONTAMINATION="true"; fi
fi

# Check ORU Folder
ORU_SUCCESS="false"
ORU_CONTAMINATION="false"
if [ -n "$(ls -A /tmp/output/oru/ 2>/dev/null)" ]; then
    if grep -q "ORU" /tmp/output/oru/* 2>/dev/null; then ORU_SUCCESS="true"; fi
    if grep -q "ADT\|ORM" /tmp/output/oru/* 2>/dev/null; then ORU_CONTAMINATION="true"; fi
fi

# 8. Detect File Writer logic in destinations (Static Analysis backup)
HAS_ADT_FILTER="false"
HAS_ORM_FILTER="false"
HAS_ORU_FILTER="false"
if [ -n "$CHANNEL_XML" ]; then
    if echo "$CHANNEL_XML" | grep -qi "ADT"; then HAS_ADT_FILTER="true"; fi
    if echo "$CHANNEL_XML" | grep -qi "ORM"; then HAS_ORM_FILTER="true"; fi
    if echo "$CHANNEL_XML" | grep -qi "ORU"; then HAS_ORU_FILTER="true"; fi
fi

# 9. Create Result JSON
JSON_CONTENT=$(cat <<EOF
{
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "channel_id": "$CHANNEL_ID",
    "channel_name": "$CHANNEL_NAME",
    "channel_status": "$CHANNEL_STATUS",
    "listen_port": "$LISTEN_PORT",
    "destination_count": $DESTINATION_COUNT,
    "routing_test": {
        "adt_success": $ADT_SUCCESS,
        "adt_contamination": $ADT_CONTAMINATION,
        "orm_success": $ORM_SUCCESS,
        "orm_contamination": $ORM_CONTAMINATION,
        "oru_success": $ORU_SUCCESS,
        "oru_contamination": $ORU_CONTAMINATION
    },
    "static_analysis": {
        "has_adt_filter": $HAS_ADT_FILTER,
        "has_orm_filter": $HAS_ORM_FILTER,
        "has_oru_filter": $HAS_ORU_FILTER
    },
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "/tmp/task_result.json" "$JSON_CONTENT"
echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json