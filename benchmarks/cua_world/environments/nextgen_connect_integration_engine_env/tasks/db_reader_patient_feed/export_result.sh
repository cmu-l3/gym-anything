#!/bin/bash
# Export script for db_reader_patient_feed task

echo "=== Exporting DB Patient Registration Feed Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Initial tracking
INITIAL_CHANNEL_COUNT=$(cat /tmp/initial_channel_count.txt 2>/dev/null || echo "0")
CURRENT_CHANNEL_COUNT=$(get_channel_count)
INITIAL_UNPROCESSED=$(cat /tmp/initial_unprocessed_count.txt 2>/dev/null || echo "0")

echo "Channel count: Initial=$INITIAL_CHANNEL_COUNT, Current=$CURRENT_CHANNEL_COUNT"

# 1. Find the channel
CHANNEL_NAME="DB_Patient_Registration_Feed"
CHANNEL_ID=""
CHANNEL_EXISTS="false"
CHANNEL_XML=""
CHANNEL_JSON=""

# Search by exact name
EXACT_ID=$(query_postgres "SELECT id FROM channel WHERE name = '$CHANNEL_NAME';" 2>/dev/null | head -1 | tr -d ' ')
if [ -n "$EXACT_ID" ]; then
    CHANNEL_ID="$EXACT_ID"
    CHANNEL_EXISTS="true"
    echo "Found channel '$CHANNEL_NAME' with ID: $CHANNEL_ID"
else
    # Fallback search
    SEARCH_ID=$(query_postgres "SELECT id FROM channel WHERE LOWER(name) LIKE '%db%' AND LOWER(name) LIKE '%patient%' LIMIT 1;" 2>/dev/null | head -1 | tr -d ' ')
    if [ -n "$SEARCH_ID" ]; then
        CHANNEL_ID="$SEARCH_ID"
        CHANNEL_EXISTS="true"
        echo "Found likely channel with ID: $CHANNEL_ID"
    fi
fi

# 2. Get Channel Configuration
SOURCE_IS_DB_READER="false"
DEST_IS_FILE_WRITER="false"
JDBC_CONFIG_CORRECT="false"
SQL_QUERY_CORRECT="false"
HAS_TRANSFORMER="false"

if [ -n "$CHANNEL_ID" ]; then
    # Fetch XML config
    CHANNEL_XML=$(query_postgres "SELECT channel FROM channel WHERE id='$CHANNEL_ID';" 2>/dev/null)
    
    # Check Source Connector
    if echo "$CHANNEL_XML" | grep -qi "Database Reader"; then
        SOURCE_IS_DB_READER="true"
    fi
    # Backup check for class name
    if echo "$CHANNEL_XML" | grep -q "com.mirth.connect.connectors.jdbc.DatabaseReceiver"; then
        SOURCE_IS_DB_READER="true"
    fi

    # Check JDBC URL
    if echo "$CHANNEL_XML" | grep -q "jdbc:postgresql://nextgen-postgres:5432/mirthdb"; then
        JDBC_CONFIG_CORRECT="true"
    fi

    # Check SQL Query
    if echo "$CHANNEL_XML" | grep -qi "patient_registrations" && echo "$CHANNEL_XML" | grep -qi "processed.*false"; then
        SQL_QUERY_CORRECT="true"
    fi

    # Check Destination
    if echo "$CHANNEL_XML" | grep -qi "File Writer"; then
        DEST_IS_FILE_WRITER="true"
    fi
    # Backup check for class name
    if echo "$CHANNEL_XML" | grep -q "com.mirth.connect.connectors.file.FileDispatcher"; then
        DEST_IS_FILE_WRITER="true"
    fi

    # Check Transformer (JavaScript step)
    if echo "$CHANNEL_XML" | grep -qi "JavaScriptStep" || echo "$CHANNEL_XML" | grep -qi "mapper"; then
        HAS_TRANSFORMER="true"
    fi
fi

# 3. Check Channel Status
CHANNEL_STARTED="false"
MESSAGES_RECEIVED=0
MESSAGES_SENT=0

if [ -n "$CHANNEL_ID" ]; then
    # Check if deployed
    STATUS_JSON=$(curl -sk -u admin:admin -H "X-Requested-With: OpenAPI" -H "Accept: application/json" "https://localhost:8443/api/channels/$CHANNEL_ID/status" 2>/dev/null)
    STATE=$(echo "$STATUS_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('dashboardStatus', {}).get('state', 'UNKNOWN'))" 2>/dev/null)
    
    if [ "$STATE" == "STARTED" ]; then
        CHANNEL_STARTED="true"
    fi

    # Check Statistics
    STATS_JSON=$(curl -sk -u admin:admin -H "X-Requested-With: OpenAPI" -H "Accept: application/json" "https://localhost:8443/api/channels/$CHANNEL_ID/statistics" 2>/dev/null)
    MESSAGES_RECEIVED=$(echo "$STATS_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('channelStatistics', {}).get('received', 0))" 2>/dev/null)
    MESSAGES_SENT=$(echo "$STATS_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('channelStatistics', {}).get('sent', 0))" 2>/dev/null)
fi

# 4. Check Output Files
OUTPUT_FILE_COUNT=0
OUTPUT_FILES_EXIST="false"
HL7_CONTENT_VALID="false"
FIRST_FILE_CONTENT=""

OUTPUT_FILE_COUNT=$(docker exec nextgen-connect find /opt/connect/outbound_hl7 -name "*.hl7" -type f 2>/dev/null | wc -l)

if [ "$OUTPUT_FILE_COUNT" -gt 0 ]; then
    OUTPUT_FILES_EXIST="true"
    
    # Check content of the first file
    FIRST_FILE=$(docker exec nextgen-connect find /opt/connect/outbound_hl7 -name "*.hl7" -type f | head -1)
    FIRST_FILE_CONTENT=$(docker exec nextgen-connect cat "$FIRST_FILE")
    
    # Simple validation: Has MSH, ADT^A04, and PID
    if echo "$FIRST_FILE_CONTENT" | grep -q "^MSH" && \
       echo "$FIRST_FILE_CONTENT" | grep -q "ADT^A04" && \
       echo "$FIRST_FILE_CONTENT" | grep -q "^PID"; then
        HL7_CONTENT_VALID="true"
    fi
fi

# 5. Check Database Updates
PROCESSED_COUNT=0
PROCESSED_COUNT=$(docker exec nextgen-postgres psql -U postgres -d mirthdb -t -A -c "SELECT COUNT(*) FROM patient_registrations WHERE processed = true;")

echo "Processed records in DB: $PROCESSED_COUNT"

# Create JSON result
JSON_CONTENT=$(cat <<EOF
{
    "initial_channel_count": $INITIAL_CHANNEL_COUNT,
    "current_channel_count": $CURRENT_CHANNEL_COUNT,
    "channel_exists": $CHANNEL_EXISTS,
    "channel_id": "$CHANNEL_ID",
    "config": {
        "source_is_db_reader": $SOURCE_IS_DB_READER,
        "dest_is_file_writer": $DEST_IS_FILE_WRITER,
        "jdbc_correct": $JDBC_CONFIG_CORRECT,
        "sql_query_correct": $SQL_QUERY_CORRECT,
        "has_transformer": $HAS_TRANSFORMER
    },
    "status": {
        "started": $CHANNEL_STARTED,
        "msgs_received": $MESSAGES_RECEIVED,
        "msgs_sent": $MESSAGES_SENT
    },
    "output": {
        "files_exist": $OUTPUT_FILES_EXIST,
        "file_count": $OUTPUT_FILE_COUNT,
        "content_valid": $HL7_CONTENT_VALID
    },
    "database": {
        "processed_count": $PROCESSED_COUNT,
        "initial_unprocessed": $INITIAL_UNPROCESSED
    },
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "/tmp/db_reader_result.json" "$JSON_CONTENT"
echo "Result saved to /tmp/db_reader_result.json"
cat /tmp/db_reader_result.json
echo "=== Export complete ==="