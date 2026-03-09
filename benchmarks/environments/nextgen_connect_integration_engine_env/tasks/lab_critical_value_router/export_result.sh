#!/bin/bash
echo "=== Exporting lab_critical_value_router task result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_critrouter.png

# Get initial and current channel counts
INITIAL=$(cat /tmp/initial_critrouter_channel_count 2>/dev/null || echo "0")
CURRENT=$(get_channel_count)

echo "Initial channel count: $INITIAL"
echo "Current channel count: $CURRENT"

# Locate the Lab Critical Value Router channel
CHANNEL_EXISTS="false"
CHANNEL_ID=""
CHANNEL_NAME=""
CHANNEL_STATUS="unknown"
LISTEN_PORT=""
DEST_COUNT=0
HAS_JS_TRANSFORMER="false"
HAS_CRITICAL_FILTER="false"
HAS_NORMAL_FILTER="false"
HAS_FILE_WRITER="false"
HAS_DB_WRITER_CRITICAL="false"
HAS_DB_WRITER_NORMAL="false"

# Search for the channel by name patterns
CHANNEL_DATA=$(query_postgres "SELECT id, name FROM channel WHERE LOWER(name) LIKE '%critical%' OR LOWER(name) LIKE '%lab%router%' OR (LOWER(name) LIKE '%lab%' AND LOWER(name) LIKE '%value%');" 2>/dev/null || true)

if [ -n "$CHANNEL_DATA" ]; then
    CHANNEL_EXISTS="true"
    CHANNEL_ID=$(echo "$CHANNEL_DATA" | head -1 | cut -d'|' -f1)
    CHANNEL_NAME=$(echo "$CHANNEL_DATA" | head -1 | cut -d'|' -f2)
    echo "Found channel: $CHANNEL_NAME (ID: $CHANNEL_ID)"
fi

# If not found, check for any new channel
if [ "$CHANNEL_EXISTS" = "false" ] && [ "$CURRENT" -gt "$INITIAL" ]; then
    LATEST_DATA=$(query_postgres "SELECT id, name FROM channel ORDER BY revision DESC LIMIT 1;" 2>/dev/null || true)
    if [ -n "$LATEST_DATA" ]; then
        CHANNEL_EXISTS="true"
        CHANNEL_ID=$(echo "$LATEST_DATA" | head -1 | cut -d'|' -f1)
        CHANNEL_NAME=$(echo "$LATEST_DATA" | head -1 | cut -d'|' -f2)
        echo "Found latest channel: $CHANNEL_NAME (ID: $CHANNEL_ID)"
    fi
fi

# Analyze channel XML configuration
if [ -n "$CHANNEL_ID" ]; then
    CHANNEL_XML=$(query_postgres "SELECT channel FROM channel WHERE id='$CHANNEL_ID';" 2>/dev/null || true)

    # Extract listen port
    LISTEN_PORT=$(echo "$CHANNEL_XML" | python3 -c "
import sys, re
xml = sys.stdin.read()
m = re.search(r'<port>(\d+)</port>', xml)
if m: print(m.group(1))
else: print('')
" 2>/dev/null || true)

    # Count destination connectors
    DEST_COUNT=$(echo "$CHANNEL_XML" | python3 -c "
import sys, re
xml = sys.stdin.read()
# Count <connector> elements inside <destinationConnectors>
m = re.search(r'<destinationConnectors>(.*?)</destinationConnectors>', xml, re.DOTALL)
if m:
    connectors = re.findall(r'<connector\b', m.group(1))
    print(len(connectors))
else:
    print(0)
" 2>/dev/null || echo "0")

    # Check for JavaScript transformer referencing OBX
    if echo "$CHANNEL_XML" | python3 -c "
import sys, re
xml = sys.stdin.read()
# Look for JS code mentioning OBX and abnormal flags
has_js = bool(re.search(r'JAVASCRIPT|javascript|msg\[.OBX.\]|OBX.*8|abnormalFlag|isCritical|HH.*LL|LL.*HH', xml, re.IGNORECASE))
print('true' if has_js else 'false')
" 2>/dev/null | grep -q "true"; then
        HAS_JS_TRANSFORMER="true"
    fi

    # Check for critical value filter logic
    if echo "$CHANNEL_XML" | grep -qi "isCritical\|critical.*filter\|HH\|LL"; then
        HAS_CRITICAL_FILTER="true"
    fi

    # Check for normal filter logic
    if echo "$CHANNEL_XML" | grep -qi "isCritical.*false\|normal.*filter\|isNormal"; then
        HAS_NORMAL_FILTER="true"
    fi

    # Check for File Writer destination
    if echo "$CHANNEL_XML" | grep -qi "FileDispatcherProperties\|fileDispatcher\|File Writer\|lab_audit"; then
        HAS_FILE_WRITER="true"
    fi

    # Check for DB writer with critical_lab_results
    if echo "$CHANNEL_XML" | grep -qi "critical_lab_results"; then
        HAS_DB_WRITER_CRITICAL="true"
    fi

    # Check for DB writer with normal_lab_results
    if echo "$CHANNEL_XML" | grep -qi "normal_lab_results"; then
        HAS_DB_WRITER_NORMAL="true"
    fi

    # Check deployment status
    DEPLOYED_CHECK=$(query_postgres "SELECT COUNT(*) FROM d_channels WHERE channel_id='$CHANNEL_ID';" 2>/dev/null || echo "0")
    if [ "$DEPLOYED_CHECK" -gt 0 ] 2>/dev/null; then
        CHANNEL_STATUS="deployed"
    fi
    API_STATUS=$(get_channel_status_api "$CHANNEL_ID" 2>/dev/null || echo "UNKNOWN")
    if [ "$API_STATUS" != "UNKNOWN" ] && [ -n "$API_STATUS" ]; then
        CHANNEL_STATUS="$API_STATUS"
    fi
fi

# Check if the PostgreSQL tables were created
CRITICAL_TABLE_EXISTS="false"
NORMAL_TABLE_EXISTS="false"
CRITICAL_ROW_COUNT=0
NORMAL_ROW_COUNT=0

CRITICAL_CHECK=$(query_postgres "SELECT COUNT(*) FROM information_schema.tables WHERE table_name='critical_lab_results';" 2>/dev/null || echo "0")
if [ "$CRITICAL_CHECK" -gt 0 ] 2>/dev/null; then
    CRITICAL_TABLE_EXISTS="true"
    CRITICAL_ROW_COUNT=$(query_postgres "SELECT COUNT(*) FROM critical_lab_results;" 2>/dev/null || echo "0")
fi

NORMAL_CHECK=$(query_postgres "SELECT COUNT(*) FROM information_schema.tables WHERE table_name='normal_lab_results';" 2>/dev/null || echo "0")
if [ "$NORMAL_CHECK" -gt 0 ] 2>/dev/null; then
    NORMAL_TABLE_EXISTS="true"
    NORMAL_ROW_COUNT=$(query_postgres "SELECT COUNT(*) FROM normal_lab_results;" 2>/dev/null || echo "0")
fi

echo "Channel: $CHANNEL_NAME (ID: $CHANNEL_ID), Port: $LISTEN_PORT, Status: $CHANNEL_STATUS"
echo "Destinations: $DEST_COUNT, JS Transformer: $HAS_JS_TRANSFORMER"
echo "File Writer: $HAS_FILE_WRITER, Critical DB: $HAS_DB_WRITER_CRITICAL, Normal DB: $HAS_DB_WRITER_NORMAL"
echo "critical_lab_results: $CRITICAL_TABLE_EXISTS ($CRITICAL_ROW_COUNT rows)"
echo "normal_lab_results: $NORMAL_TABLE_EXISTS ($NORMAL_ROW_COUNT rows)"

# Create JSON result
JSON_CONTENT=$(cat <<EOF
{
    "initial_count": $INITIAL,
    "current_count": $CURRENT,
    "channel_exists": $CHANNEL_EXISTS,
    "channel_id": "$CHANNEL_ID",
    "channel_name": "$CHANNEL_NAME",
    "channel_status": "$CHANNEL_STATUS",
    "listen_port": "$LISTEN_PORT",
    "destination_count": $DEST_COUNT,
    "has_js_transformer": $HAS_JS_TRANSFORMER,
    "has_critical_filter": $HAS_CRITICAL_FILTER,
    "has_normal_filter": $HAS_NORMAL_FILTER,
    "has_file_writer": $HAS_FILE_WRITER,
    "has_db_writer_critical": $HAS_DB_WRITER_CRITICAL,
    "has_db_writer_normal": $HAS_DB_WRITER_NORMAL,
    "critical_table_exists": $CRITICAL_TABLE_EXISTS,
    "normal_table_exists": $NORMAL_TABLE_EXISTS,
    "critical_row_count": $CRITICAL_ROW_COUNT,
    "normal_row_count": $NORMAL_ROW_COUNT,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "/tmp/lab_critical_value_router_result.json" "$JSON_CONTENT"

echo "Result saved to /tmp/lab_critical_value_router_result.json"
cat /tmp/lab_critical_value_router_result.json
echo "=== Export complete ==="
