#!/bin/bash
echo "=== Exporting setup_database_writer task result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Get initial and current channel counts
INITIAL=$(cat /tmp/initial_dbwriter_channel_count 2>/dev/null || echo "0")
CURRENT=$(get_channel_count)

echo "Initial channel count: $INITIAL"
echo "Current channel count: $CURRENT"

# Check for DB writer channel
DB_CHANNEL_EXISTS="false"
CHANNEL_ID=""
CHANNEL_NAME=""
HAS_DB_WRITER="false"
CHANNEL_STATUS="unknown"
LISTEN_PORT=""

# Query for channels with "db" or "database" or "patient" or "writer" in the name
DB_QUERY="SELECT id, name FROM channel WHERE LOWER(name) LIKE '%db%' OR LOWER(name) LIKE '%database%' OR LOWER(name) LIKE '%patient%' OR LOWER(name) LIKE '%writer%';"
DB_DATA=$(query_postgres "$DB_QUERY" 2>/dev/null || true)

if [ -n "$DB_DATA" ]; then
    DB_CHANNEL_EXISTS="true"
    CHANNEL_ID=$(echo "$DB_DATA" | head -1 | cut -d'|' -f1)
    CHANNEL_NAME=$(echo "$DB_DATA" | head -1 | cut -d'|' -f2)
    echo "Found DB writer channel: $CHANNEL_NAME (ID: $CHANNEL_ID)"

    # Check channel XML config for database writer elements
    CHANNEL_XML=$(query_postgres "SELECT channel FROM channel WHERE id='$CHANNEL_ID';" 2>/dev/null || true)
    if echo "$CHANNEL_XML" | grep -qi "DatabaseDispatcher\|jdbc\|database.*writer\|INSERT.*INTO\|patient_records"; then
        HAS_DB_WRITER="true"
        echo "Database writer destination detected in channel configuration"
    fi

    # Extract listening port
    LISTEN_PORT=$(echo "$CHANNEL_XML" | python3 -c "
import sys, re
xml = sys.stdin.read()
m = re.search(r'<port>(\d+)</port>', xml)
if m: print(m.group(1))
else: print('')
" 2>/dev/null || true)
fi

# If exact match not found, check for any new channel
if [ "$DB_CHANNEL_EXISTS" = "false" ] && [ "$CURRENT" -gt "$INITIAL" ]; then
    LATEST_DATA=$(query_postgres "SELECT id, name FROM channel ORDER BY revision DESC LIMIT 1;" 2>/dev/null || true)
    if [ -n "$LATEST_DATA" ]; then
        DB_CHANNEL_EXISTS="true"
        CHANNEL_ID=$(echo "$LATEST_DATA" | head -1 | cut -d'|' -f1)
        CHANNEL_NAME=$(echo "$LATEST_DATA" | head -1 | cut -d'|' -f2)
        echo "Found latest channel: $CHANNEL_NAME (ID: $CHANNEL_ID)"

        CHANNEL_XML=$(query_postgres "SELECT channel FROM channel WHERE id='$CHANNEL_ID';" 2>/dev/null || true)
        if echo "$CHANNEL_XML" | grep -qi "DatabaseDispatcher\|jdbc\|database.*writer\|INSERT.*INTO\|patient_records"; then
            HAS_DB_WRITER="true"
        fi

        LISTEN_PORT=$(echo "$CHANNEL_XML" | python3 -c "
import sys, re
xml = sys.stdin.read()
m = re.search(r'<port>(\d+)</port>', xml)
if m: print(m.group(1))
else: print('')
" 2>/dev/null || true)
    fi
fi

# Check deployment status
if [ -n "$CHANNEL_ID" ]; then
    DEPLOYED_CHECK=$(query_postgres "SELECT COUNT(*) FROM d_channels WHERE channel_id='$CHANNEL_ID';" 2>/dev/null || echo "0")
    if [ "$DEPLOYED_CHECK" -gt 0 ] 2>/dev/null; then
        CHANNEL_STATUS="deployed"
    fi
    API_STATUS=$(get_channel_status_api "$CHANNEL_ID" 2>/dev/null || echo "UNKNOWN")
    if [ "$API_STATUS" != "UNKNOWN" ] && [ -n "$API_STATUS" ]; then
        CHANNEL_STATUS="$API_STATUS"
    fi
fi

# Check if patient_records table was created
TABLE_EXISTS="false"
RECORD_COUNT=0
TABLE_CHECK=$(query_postgres "SELECT COUNT(*) FROM information_schema.tables WHERE table_name='patient_records';" 2>/dev/null || echo "0")
if [ "$TABLE_CHECK" -gt 0 ] 2>/dev/null; then
    TABLE_EXISTS="true"
    RECORD_COUNT=$(query_postgres "SELECT COUNT(*) FROM patient_records;" 2>/dev/null || echo "0")
    echo "patient_records table exists with $RECORD_COUNT records"
fi

echo "Listen port: $LISTEN_PORT, DB Writer: $HAS_DB_WRITER, Status: $CHANNEL_STATUS"

# Create JSON result
JSON_CONTENT=$(cat <<EOF
{
    "initial_count": $INITIAL,
    "current_count": $CURRENT,
    "db_channel_exists": $DB_CHANNEL_EXISTS,
    "channel_id": "$CHANNEL_ID",
    "channel_name": "$CHANNEL_NAME",
    "has_db_writer": $HAS_DB_WRITER,
    "channel_status": "$CHANNEL_STATUS",
    "listen_port": "$LISTEN_PORT",
    "table_exists": $TABLE_EXISTS,
    "record_count": $RECORD_COUNT,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "/tmp/setup_database_writer_result.json" "$JSON_CONTENT"

echo "Result saved to /tmp/setup_database_writer_result.json"
cat /tmp/setup_database_writer_result.json
echo "=== Export complete ==="
