#!/bin/bash
echo "=== Exporting custom_metadata_columns results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Define expected output structure
RESULT_FILE="/tmp/task_result.json"

# 3. Find the channel by name
CHANNEL_ID=""
CHANNEL_NAME="ADT_Metadata_Tracker"
CHANNEL_ID_QUERY="SELECT id FROM channel WHERE name = '$CHANNEL_NAME';"
CHANNEL_ID=$(query_postgres "$CHANNEL_ID_QUERY")

CHANNEL_EXISTS="false"
CHANNEL_STATUS="UNKNOWN"
COLUMNS_DEFINED="false"
TRANSFORMER_STEPS="false"
MSG_COUNT=0
ERROR_COUNT=0
METADATA_VERIFICATION="[]"
FILE_OUTPUT_COUNT=0

if [ -n "$CHANNEL_ID" ]; then
    CHANNEL_EXISTS="true"
    echo "Found channel ID: $CHANNEL_ID"

    # 4. Get Channel Status via API
    STATUS_JSON=$(curl -sk -u admin:admin -H "X-Requested-With: OpenAPI" -H "Accept: application/json" "https://localhost:8443/api/channels/${CHANNEL_ID}/status")
    CHANNEL_STATUS=$(echo "$STATUS_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('dashboardStatus', {}).get('state', 'UNKNOWN'))" 2>/dev/null || echo "UNKNOWN")

    # 5. Get Channel Config via API to check metadata columns
    CONFIG_JSON=$(curl -sk -u admin:admin -H "X-Requested-With: OpenAPI" -H "Accept: application/json" "https://localhost:8443/api/channels/${CHANNEL_ID}")
    
    # Check if metadata columns exist in the source connector properties
    COLUMNS_DEFINED=$(echo "$CONFIG_JSON" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    meta = data['sourceConnector']['properties']['pluginProperties']['com.mirth.connect.plugins.datatypes.hl7v2.HL7v2DataTypeProperties']
    # Note: In JSON export, custom metadata is often likely in properties or sourceConnector properties depending on version
    # Actually, for 4.x, metadata columns are top-level on the channel object or source connector?
    # Let's check sourceConnector.metaDataColumns
    cols = data['sourceConnector'].get('metaDataColumns', [])
    names = [c['name'] for c in cols]
    required = ['PatientMRN', 'PatientName', 'EventType']
    print(all(r in names for r in required))
except:
    print('false')
" 2>/dev/null || echo "false")

    # Check for transformer steps
    TRANSFORMER_STEPS=$(echo "$CONFIG_JSON" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    steps = data['sourceConnector']['transformer']['elements']
    print('true' if len(steps) > 0 else 'false')
except:
    print('false')
" 2>/dev/null || echo "false")

    # 6. Get Message Statistics
    STATS_JSON=$(curl -sk -u admin:admin -H "X-Requested-With: OpenAPI" -H "Accept: application/json" "https://localhost:8443/api/channels/${CHANNEL_ID}/statistics")
    MSG_COUNT=$(echo "$STATS_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('channelStatistics', {}).get('received', 0))" 2>/dev/null || echo "0")
    ERROR_COUNT=$(echo "$STATS_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('channelStatistics', {}).get('error', 0))" 2>/dev/null || echo "0")

    # 7. Inspect Processed Messages for Metadata Values (Crucial Step)
    # We fetch the last 10 messages and look at their custom metadata map
    MESSAGES_JSON=$(curl -sk -u admin:admin -H "X-Requested-With: OpenAPI" -H "Accept: application/json" "https://localhost:8443/api/channels/${CHANNEL_ID}/messages?includeContent=false&limit=10")
    
    METADATA_VERIFICATION=$(echo "$MESSAGES_JSON" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    results = []
    messages = data.get('list', [])
    for msg in messages:
        # metadataMap contains the custom column values
        meta = msg.get('connectorMessages', {}).get('0', {}).get('metaDataMap', {})
        results.append({
            'id': msg.get('messageId'),
            'PatientMRN': meta.get('PatientMRN', ''),
            'PatientName': meta.get('PatientName', ''),
            'EventType': meta.get('EventType', '')
        })
    print(json.dumps(results))
except Exception as e:
    print('[]')
" 2>/dev/null || echo "[]")

fi

# 8. Check File Output
if [ -d "/tmp/adt_output" ]; then
    FILE_OUTPUT_COUNT=$(ls -1 /tmp/adt_output/*.hl7 2>/dev/null | wc -l)
fi

# 9. Create Result JSON
cat > "$RESULT_FILE" <<EOF
{
    "channel_exists": $CHANNEL_EXISTS,
    "channel_status": "$CHANNEL_STATUS",
    "columns_defined": $COLUMNS_DEFINED,
    "transformer_steps_exist": $TRANSFORMER_STEPS,
    "message_count": $MSG_COUNT,
    "error_count": $ERROR_COUNT,
    "file_output_count": $FILE_OUTPUT_COUNT,
    "metadata_verification": $METADATA_VERIFICATION,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Make readable
chmod 666 "$RESULT_FILE"
echo "Result exported to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export Complete ==="