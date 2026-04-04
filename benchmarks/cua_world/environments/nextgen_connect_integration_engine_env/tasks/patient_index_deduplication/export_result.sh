#!/bin/bash
echo "=== Exporting patient_index_deduplication task result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_pmisync.png

# Get initial and current channel counts
INITIAL=$(cat /tmp/initial_pmisync_channel_count 2>/dev/null || echo "0")
CURRENT=$(get_channel_count)

echo "Initial channel count: $INITIAL"
echo "Current channel count: $CURRENT"

# Locate the Patient Master Index Sync channel
CHANNEL_EXISTS="false"
CHANNEL_ID=""
CHANNEL_NAME=""
CHANNEL_STATUS="unknown"
LISTEN_PORT=""
HAS_JS_TRANSFORMER="false"
HAS_UPSERT_SQL="false"
HAS_RESPONSE_TRANSFORMER="false"
HAS_PID_EXTRACTION="false"
DB_DEST_EXISTS="false"

# Search by name patterns
CHANNEL_DATA=$(query_postgres "SELECT id, name FROM channel WHERE LOWER(name) LIKE '%patient%' AND (LOWER(name) LIKE '%master%' OR LOWER(name) LIKE '%index%' OR LOWER(name) LIKE '%sync%' OR LOWER(name) LIKE '%pmi%' OR LOWER(name) LIKE '%dedup%');" 2>/dev/null || true)

if [ -n "$CHANNEL_DATA" ]; then
    CHANNEL_EXISTS="true"
    CHANNEL_ID=$(echo "$CHANNEL_DATA" | head -1 | cut -d'|' -f1)
    CHANNEL_NAME=$(echo "$CHANNEL_DATA" | head -1 | cut -d'|' -f2)
    echo "Found PMI channel: $CHANNEL_NAME (ID: $CHANNEL_ID)"
fi

# Broader search if not found
if [ "$CHANNEL_EXISTS" = "false" ]; then
    CHANNEL_DATA2=$(query_postgres "SELECT id, name FROM channel WHERE LOWER(name) LIKE '%master%index%' OR LOWER(name) LIKE '%patient.*sync%' LIMIT 1;" 2>/dev/null || true)
    if [ -n "$CHANNEL_DATA2" ]; then
        CHANNEL_EXISTS="true"
        CHANNEL_ID=$(echo "$CHANNEL_DATA2" | head -1 | cut -d'|' -f1)
        CHANNEL_NAME=$(echo "$CHANNEL_DATA2" | head -1 | cut -d'|' -f2)
    fi
fi

# Fallback: any new channel
if [ "$CHANNEL_EXISTS" = "false" ] && [ "$CURRENT" -gt "$INITIAL" ]; then
    LATEST_DATA=$(query_postgres "SELECT id, name FROM channel ORDER BY revision DESC LIMIT 1;" 2>/dev/null || true)
    if [ -n "$LATEST_DATA" ]; then
        CHANNEL_EXISTS="true"
        CHANNEL_ID=$(echo "$LATEST_DATA" | head -1 | cut -d'|' -f1)
        CHANNEL_NAME=$(echo "$LATEST_DATA" | head -1 | cut -d'|' -f2)
        echo "Fallback - Found latest channel: $CHANNEL_NAME (ID: $CHANNEL_ID)"
    fi
fi

# Analyze channel XML
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

    # Check for JavaScript transformer with PID extraction
    if echo "$CHANNEL_XML" | python3 -c "
import sys, re
xml = sys.stdin.read()
has_js = bool(re.search(r'JAVASCRIPT|msg\[.PID.\]|PID.*\[|channelMap|mrn|last_name|patient_master', xml, re.IGNORECASE))
print('true' if has_js else 'false')
" 2>/dev/null | grep -q "true"; then
        HAS_JS_TRANSFORMER="true"
    fi

    # Check specifically for PID segment extraction
    if echo "$CHANNEL_XML" | grep -qi "PID\|channelMap\|mrn\|last_name\|first_name"; then
        HAS_PID_EXTRACTION="true"
    fi

    # Check for ON CONFLICT / upsert SQL
    if echo "$CHANNEL_XML" | grep -qi "ON CONFLICT\|on conflict\|UPSERT\|upsert\|DO UPDATE"; then
        HAS_UPSERT_SQL="true"
    fi

    # Check for database writer destination
    if echo "$CHANNEL_XML" | grep -qi "DatabaseDispatcher\|DatabaseDispatcherProperties\|patient_master_index\|jdbc:postgresql"; then
        DB_DEST_EXISTS="true"
    fi

    # Check for response transformer
    if echo "$CHANNEL_XML" | grep -qi "<responseTransformer>"; then
        HAS_RESPONSE_TRANSFORMER="true"
    fi

    # Check deployment
    DEPLOYED_CHECK=$(query_postgres "SELECT COUNT(*) FROM d_channels WHERE channel_id='$CHANNEL_ID';" 2>/dev/null || echo "0")
    if [ "$DEPLOYED_CHECK" -gt 0 ] 2>/dev/null; then
        CHANNEL_STATUS="deployed"
    fi
    API_STATUS=$(get_channel_status_api "$CHANNEL_ID" 2>/dev/null || echo "UNKNOWN")
    if [ "$API_STATUS" != "UNKNOWN" ] && [ -n "$API_STATUS" ]; then
        CHANNEL_STATUS="$API_STATUS"
    fi
fi

# Check patient_master_index table
PMI_TABLE_EXISTS="false"
PMI_ROW_COUNT=0
PMI_HAS_UNIQUE="false"

PMI_CHECK=$(query_postgres "SELECT COUNT(*) FROM information_schema.tables WHERE table_name='patient_master_index';" 2>/dev/null || echo "0")
if [ "$PMI_CHECK" -gt 0 ] 2>/dev/null; then
    PMI_TABLE_EXISTS="true"
    PMI_ROW_COUNT=$(query_postgres "SELECT COUNT(*) FROM patient_master_index;" 2>/dev/null || echo "0")

    # Check if mrn column has unique/pk constraint
    UNIQUE_CHECK=$(query_postgres "SELECT COUNT(*) FROM information_schema.table_constraints tc JOIN information_schema.key_column_usage kcu ON tc.constraint_name=kcu.constraint_name WHERE tc.table_name='patient_master_index' AND kcu.column_name='mrn' AND tc.constraint_type IN ('PRIMARY KEY','UNIQUE');" 2>/dev/null || echo "0")
    if [ "$UNIQUE_CHECK" -gt 0 ] 2>/dev/null; then
        PMI_HAS_UNIQUE="true"
    fi
fi

echo "Channel: $CHANNEL_NAME, Port: $LISTEN_PORT, Status: $CHANNEL_STATUS"
echo "JS Transformer: $HAS_JS_TRANSFORMER, PID Extraction: $HAS_PID_EXTRACTION"
echo "Upsert SQL: $HAS_UPSERT_SQL, DB Dest: $DB_DEST_EXISTS"
echo "Response Transformer: $HAS_RESPONSE_TRANSFORMER"
echo "patient_master_index table: $PMI_TABLE_EXISTS (rows: $PMI_ROW_COUNT, unique mrn: $PMI_HAS_UNIQUE)"

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
    "has_js_transformer": $HAS_JS_TRANSFORMER,
    "has_pid_extraction": $HAS_PID_EXTRACTION,
    "has_upsert_sql": $HAS_UPSERT_SQL,
    "has_db_dest": $DB_DEST_EXISTS,
    "has_response_transformer": $HAS_RESPONSE_TRANSFORMER,
    "pmi_table_exists": $PMI_TABLE_EXISTS,
    "pmi_row_count": $PMI_ROW_COUNT,
    "pmi_has_unique_mrn": $PMI_HAS_UNIQUE,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "/tmp/patient_index_deduplication_result.json" "$JSON_CONTENT"

echo "Result saved to /tmp/patient_index_deduplication_result.json"
cat /tmp/patient_index_deduplication_result.json
echo "=== Export complete ==="
