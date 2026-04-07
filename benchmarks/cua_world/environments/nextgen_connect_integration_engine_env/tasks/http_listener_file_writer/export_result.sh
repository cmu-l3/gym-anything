#!/bin/bash
echo "=== Exporting HTTP Listener File Writer results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Initial data
INITIAL_COUNT=$(cat /tmp/initial_channel_count.txt 2>/dev/null || echo "0")
CURRENT_COUNT=$(get_channel_count)
echo "Channel count: $INITIAL_COUNT -> $CURRENT_COUNT"

# 1. Check Channel Existence & Configuration via API
CHANNEL_FOUND="false"
CHANNEL_ID=""
CHANNEL_NAME=""
HTTP_LISTENER="false"
FILE_WRITER="false"
PORT_CORRECT="false"
PATH_CORRECT="false"
CHANNEL_STATUS="UNKNOWN"
STATS_RECEIVED=0

# Search for channel
CHANNELS_JSON=$(api_call_json GET "/channels" 2>/dev/null)

# Helper python script to parse complex JSON/XML config
# We extract ID where name matches ADT_Audit_HTTP
CHANNEL_ID=$(echo "$CHANNELS_JSON" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    channels = data.get('list', []) if isinstance(data, dict) else data
    for c in channels:
        if 'ADT_Audit_HTTP' in c.get('name', ''):
            print(c.get('id', ''))
            break
except: pass
")

if [ -n "$CHANNEL_ID" ]; then
    CHANNEL_FOUND="true"
    
    # Get specific channel details
    CHANNEL_JSON=$(api_call_json GET "/channels/$CHANNEL_ID" 2>/dev/null)
    
    # Check Source: HTTP Listener on 6661
    # Note: JSON structure varies, checking raw string for robustness
    if echo "$CHANNEL_JSON" | grep -qi "HttpReceiverProperties" || echo "$CHANNEL_JSON" | grep -qi "HTTP Listener"; then
        HTTP_LISTENER="true"
    fi
    if echo "$CHANNEL_JSON" | grep -q "6661"; then
        PORT_CORRECT="true"
    fi
    
    # Check Destination: File Writer to /home/ga/output
    if echo "$CHANNEL_JSON" | grep -qi "FileWriterProperties" || echo "$CHANNEL_JSON" | grep -qi "File Writer"; then
        FILE_WRITER="true"
    fi
    if echo "$CHANNEL_JSON" | grep -q "/home/ga/output"; then
        PATH_CORRECT="true"
    fi

    # Check Status
    STATUS_JSON=$(api_call_json GET "/channels/$CHANNEL_ID/status" 2>/dev/null)
    CHANNEL_STATUS=$(echo "$STATUS_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('dashboardStatus', {}).get('state', 'UNKNOWN'))" 2>/dev/null)

    # Check Statistics
    STATS_JSON=$(api_call_json GET "/channels/$CHANNEL_ID/statistics" 2>/dev/null)
    STATS_RECEIVED=$(echo "$STATS_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('channelStatistics', {}).get('received', 0))" 2>/dev/null)
fi

# 2. Check Database (Anti-gaming / Backup check)
DB_CHANNEL_COUNT=$(query_postgres "SELECT COUNT(*) FROM channel WHERE name LIKE '%ADT_Audit_HTTP%';" 2>/dev/null || echo "0")
if [ "$DB_CHANNEL_COUNT" -gt 0 ]; then
    DB_CONFIRMED="true"
else
    DB_CONFIRMED="false"
fi

# 3. Check Output Files
FILE_CREATED="false"
HL7_CONTENT="false"
FILE_COUNT=$(ls -1 /home/ga/output/ 2>/dev/null | wc -l)

if [ "$FILE_COUNT" -gt 0 ]; then
    FILE_CREATED="true"
    # Check content of the first file
    FIRST_FILE=$(ls -1 /home/ga/output/ | head -1)
    if grep -q "MSH|" "/home/ga/output/$FIRST_FILE"; then
        HL7_CONTENT="true"
    fi
fi

# 4. Message Processing Test (Active Verification)
# We send a test message NOW to verify it works, even if the agent already did.
# This proves the channel is currently functional.
TEST_PROCESSED="false"
if [ "$CHANNEL_STATUS" == "STARTED" ]; then
    TEST_MSG="MSH|^~\&|VERIFY|TEST|CONNECT|AUDIT|20240115130000||ADT^A01|VMSG999|P|2.3|"
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H "Content-Type: text/plain" -d "$TEST_MSG" http://localhost:6661 2>/dev/null)
    
    if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "202" ]]; then
        TEST_PROCESSED="true"
        # Wait a moment for file writer
        sleep 2
        # Re-check file count
        NEW_FILE_COUNT=$(ls -1 /home/ga/output/ 2>/dev/null | wc -l)
        if [ "$NEW_FILE_COUNT" -gt "$FILE_COUNT" ]; then
            TEST_FILE_WRITTEN="true"
        else
            TEST_FILE_WRITTEN="false"
        fi
    else
        TEST_FILE_WRITTEN="false"
    fi
else
    TEST_FILE_WRITTEN="false"
fi

# Construct JSON result
cat > /tmp/task_result.json << EOF
{
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "channel_found": $CHANNEL_FOUND,
    "channel_id": "$CHANNEL_ID",
    "db_confirmed": $DB_CONFIRMED,
    "http_listener": $HTTP_LISTENER,
    "port_correct": $PORT_CORRECT,
    "file_writer": $FILE_WRITER,
    "path_correct": $PATH_CORRECT,
    "status": "$CHANNEL_STATUS",
    "stats_received": $STATS_RECEIVED,
    "file_created": $FILE_CREATED,
    "hl7_content": $HL7_CONTENT,
    "test_message_processed": $TEST_PROCESSED,
    "test_file_written": $TEST_FILE_WRITTEN,
    "file_count": $FILE_COUNT,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json